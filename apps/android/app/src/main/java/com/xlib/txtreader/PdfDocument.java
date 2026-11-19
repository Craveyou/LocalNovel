package com.xlib.txtreader;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.RectF;
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader;
import com.tom_roush.pdfbox.io.MemoryUsageSetting;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import com.tom_roush.pdfbox.pdmodel.PDPage;
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException;
import com.tom_roush.pdfbox.rendering.PDFRenderer;
import com.tom_roush.pdfbox.text.PDFTextStripper;
import com.tom_roush.pdfbox.text.TextPosition;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CancellationException;

/** Worker-owned PDF session. Decrypted content and rendered pages stay in memory. */
final class PdfDocument implements AutoCloseable {
    static final long MAX_FILE_BYTES = 256L * 1024 * 1024;
    // UTF-16 content plus an allowance per entry; never a disk text index.
    static final int SEARCH_CACHE_BYTES = 8 * 1024 * 1024;
    private final Map<Integer, String> searchCache = new LinkedHashMap<>(16, .75f, true);
    private int searchCacheBytes;
    private final PDDocument document;
    private android.graphics.pdf.PdfRenderer nativeRenderer;
    private final List<PDPage> pages = new ArrayList<>();
    final int pageCount;
    final boolean mayExtract;

    PdfDocument(Context context, File file, String password) throws IOException {
        if (file.length() > MAX_FILE_BYTES) throw new IOException("PDF 超过 256 MiB，请选择较小的文件");
        PDFBoxResourceLoader.init(context.getApplicationContext());
        document = PDDocument.load(file, password == null ? "" : password,
                MemoryUsageSetting.setupMainMemoryOnly(96L * 1024 * 1024));
        pageCount = document.getNumberOfPages();
        if (pageCount < 1 || pageCount > 100_000) { document.close(); throw new IOException("PDF 页数无效或超过支持范围"); }
        // Resolve the page tree once. Repeated indexed access walks flat page trees.
        for (PDPage page : document.getPages()) pages.add(page);
        mayExtract = document.getCurrentAccessPermission().canExtractContent();
        // Android's native renderer avoids Java rasterization on ordinary PDFs.
        // Password/unsupported files retain the existing PDFBox rendering path.
        if(!document.isEncrypted()) {
            android.os.ParcelFileDescriptor descriptor=null;
            try {
                descriptor=android.os.ParcelFileDescriptor.open(file,android.os.ParcelFileDescriptor.MODE_READ_ONLY);
                nativeRenderer=new android.graphics.pdf.PdfRenderer(descriptor);
                descriptor=null; // PdfRenderer owns the descriptor after construction.
            }catch(IOException|RuntimeException|LinkageError unavailable){if(descriptor!=null)try{descriptor.close();}catch(IOException ignored){}}
        }
    }

    static void validate(Context context, File file) throws IOException {
        try (PdfDocument ignored = new PdfDocument(context, file, null)) { }
        catch (InvalidPasswordException needsPassword) {
            // A successfully parsed encrypted document is retained for the opening-password flow.
        }
    }

    synchronized Page render(int index, int width) throws IOException {
        if (index < 0 || index >= pageCount) throw new IOException("页码超出文档范围");
        PDPage page = pages.get(index);
        checkImageCodecs(page.getResources(),new java.util.HashSet<>());
        boolean rotated = Math.floorMod(page.getRotation(), 180) != 0;
        float pointsWide = rotated ? page.getCropBox().getHeight() : page.getCropBox().getWidth();
        float pointsHigh = rotated ? page.getCropBox().getWidth() : page.getCropBox().getHeight();
        float scale = Math.min(Math.max(400, Math.min(width, 1600)) / Math.max(1, pointsWide),
                (float) Math.sqrt(4_000_000d / Math.max(1d, pointsWide * pointsHigh)));
        Bitmap bitmap=null;
        if(nativeRenderer!=null){
            try(android.graphics.pdf.PdfRenderer.Page nativePage=nativeRenderer.openPage(index)){
                bitmap=Bitmap.createBitmap(Math.max(1,Math.round(pointsWide*scale)),Math.max(1,Math.round(pointsHigh*scale)),Bitmap.Config.ARGB_8888);
                bitmap.eraseColor(android.graphics.Color.WHITE);
                nativePage.render(bitmap,null,null,android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
            }catch(RuntimeException|LinkageError unsupported){
                if(bitmap!=null){bitmap.recycle();bitmap=null;}
                // Some framework implementations cannot render this PDF. Keep the established fallback.
                nativeRenderer.close();nativeRenderer=null;
            }
        }
        if(bitmap==null){
            PDFRenderer renderer = new PDFRenderer(document);renderer.setSubsamplingAllowed(true);bitmap=renderer.renderImage(index, scale);
        }
        Text text;
        try { text=text(index); } catch(IOException extractionFailure){text=new Text("",new ArrayList<>());}
        return new Page(bitmap, text.value, text.boxes, pointsWide, pointsHigh);
    }

    private static void checkImageCodecs(com.tom_roush.pdfbox.pdmodel.PDResources resources,java.util.Set<com.tom_roush.pdfbox.cos.COSBase> visited)throws IOException {
        if(resources==null||!visited.add(resources.getCOSObject()))return;
        for(com.tom_roush.pdfbox.cos.COSName name:resources.getXObjectNames()){
            com.tom_roush.pdfbox.pdmodel.graphics.PDXObject object=resources.getXObject(name);
            if(object instanceof com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject){
                com.tom_roush.pdfbox.cos.COSBase filters=object.getCOSObject().getDictionaryObject(com.tom_roush.pdfbox.cos.COSName.FILTER);
                String value=String.valueOf(filters);
                if(value.contains("JPXDecode")||value.contains("JBIG2Decode"))throw new IOException("此 PDF 包含暂不支持的 JPEG2000/JBIG2 图片编码");
            }else if(object instanceof com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject)checkImageCodecs(((com.tom_roush.pdfbox.pdmodel.graphics.form.PDFormXObject)object).getResources(),visited);
        }
    }

    synchronized Text text(int index) throws IOException {
        return text(index, () -> false);
    }

    synchronized Text text(int index, DocumentSearch.Cancellation cancelled) throws IOException {
        Text result = extract(index, true, cancelled);
        cache(index, result.value);
        return result;
    }

    synchronized String searchText(int index) throws IOException {
        return searchText(index, () -> false);
    }

    synchronized String searchText(int index, DocumentSearch.Cancellation cancelled) throws IOException {
        checkCancelled(cancelled);
        String cached = searchCache.get(index);
        if (cached != null) return cached;
        String value = extract(index, false, cancelled).value;
        cache(index, value);
        return value;
    }

    private void cache(int index, String value) {
        if (value.length() > (SEARCH_CACHE_BYTES - 64) / 2) return;
        int bytes = cacheBytes(value);
        String previous = searchCache.put(index, value);
        if (previous != null) searchCacheBytes -= cacheBytes(previous);
        searchCacheBytes += bytes;
        java.util.Iterator<String> oldest = searchCache.values().iterator();
        while (searchCacheBytes > SEARCH_CACHE_BYTES && oldest.hasNext()) {
            searchCacheBytes -= cacheBytes(oldest.next()); oldest.remove();
        }
    }

    private static int cacheBytes(String value) { return value.length() * 2 + 64; }
    synchronized void clearSearchCache() { searchCache.clear(); searchCacheBytes = 0; }
    private static void checkCancelled(DocumentSearch.Cancellation cancelled) {
        if (cancelled.isCancelled() || Thread.currentThread().isInterrupted()) throw new CancellationException();
    }

    private Text extract(int index, boolean geometry, DocumentSearch.Cancellation cancelled) throws IOException {
        checkCancelled(cancelled);
        if (!mayExtract) return new Text("", new ArrayList<>());
        Collector collector = new Collector(pages.get(index), geometry, cancelled);
        collector.setSortByPosition(true);
        // The collector processes one resolved page directly; its local page number is 0.
        collector.setStartPage(0); collector.setEndPage(0);
        collector.getText(document);
        checkCancelled(cancelled);
        return new Text(collector.text.toString(), collector.boxes);
    }

    synchronized float pageHeight(int index) {
        PDPage page = pages.get(index);
        return Math.floorMod(page.getRotation(), 180) == 0 ? page.getCropBox().getHeight() : page.getCropBox().getWidth();
    }

    @Override public synchronized void close() throws IOException {
        clearSearchCache(); pages.clear();if(nativeRenderer!=null){nativeRenderer.close();nativeRenderer=null;}document.close();
    }

    static final class Text {
        final String value;
        final List<RectF> boxes;
        Text(String value, List<RectF> boxes) { this.value = value; this.boxes = boxes; }
    }
    static final class Page {
        final Bitmap bitmap;
        final String text;
        final List<RectF> boxes;
        final float width, height;
        Page(Bitmap bitmap, String text, List<RectF> boxes, float width, float height) {
            this.bitmap = bitmap; this.text = text; this.boxes = boxes; this.width = width; this.height = height;
        }
    }
    private static final class Collector extends PDFTextStripper {
        final StringBuilder text = new StringBuilder();
        final List<RectF> boxes = new ArrayList<>();
        final PDPage page;
        final boolean captureGeometry;
        final DocumentSearch.Cancellation cancelled;
        private int glyphs;
        Collector(PDPage page, boolean geometry, DocumentSearch.Cancellation cancelled) throws IOException {
            this.page=page; captureGeometry=geometry; this.cancelled=cancelled;
        }
        @Override protected void processTextPosition(TextPosition position) {
            // Bound cancellation latency within a page without a volatile/callback
            // read for every glyph in a full-book scan.
            if ((glyphs++ & 63) == 0) checkCancelled(cancelled);
            super.processTextPosition(position);
        }
        @Override protected void processPages(com.tom_roush.pdfbox.pdmodel.PDPageTree ignored) throws IOException {
            // PDFTextStripper otherwise walks every page for each one-page extraction,
            // making a full-book search quadratic in the number of pages.
            processPage(page);
        }
        private RectF geometry(TextPosition p) {
            float x=p.getTextMatrix().getTranslateX(), y=p.getTextMatrix().getTranslateY();
            double angle=Math.toRadians(p.getDir());
            float ax=(float)Math.cos(angle), ay=(float)Math.sin(angle);
            float w=p.getWidthDirAdj(), h=p.getHeightDir();
            float width=page.getCropBox().getWidth(), height=page.getCropBox().getHeight();
            RectF result=new RectF(Float.POSITIVE_INFINITY,Float.POSITIVE_INFINITY,Float.NEGATIVE_INFINITY,Float.NEGATIVE_INFINITY);
            int rotation=Math.floorMod(page.getRotation(),360);
            for(int a=0;a<2;a++)for(int b=0;b<2;b++){
                float px=x+a*ax*w-b*ay*h, py=y+a*ay*w+b*ax*h;
                float tx=px,ty=height-py;
                if(rotation==90){tx=py;ty=px;}
                else if(rotation==180){tx=width-px;ty=py;}
                else if(rotation==270){tx=height-py;ty=width-px;}
                result.left=Math.min(result.left,tx);result.right=Math.max(result.right,tx);
                result.top=Math.min(result.top,ty);result.bottom=Math.max(result.bottom,ty);
            }
            return result;
        }
        private void separator(String value) { text.append(value); if(captureGeometry)for (int i = 0; i < value.length(); i++) boxes.add(new RectF()); }
        @Override protected void writeString(String value, List<TextPosition> positions) {
            int emitted=0;
            for (TextPosition position : positions) {
                if ((emitted++ & 63) == 0) checkCancelled(cancelled);
                String unicode = position.getUnicode();
                if (unicode == null) continue;
                text.append(unicode);
                if(!captureGeometry)continue;
                RectF box=geometry(position);
                for (int i = 0; i < unicode.length(); i++) boxes.add(new RectF(box));
            }
        }
        @Override protected void writeWordSeparator() { separator(" "); }
        @Override protected void writeLineSeparator() { separator("\n"); }
        @Override protected void writeParagraphSeparator() { separator("\n"); }
    }
}
