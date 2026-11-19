package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import com.tom_roush.pdfbox.pdmodel.PDPage;
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream;
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission;
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException;
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy;
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import java.io.File;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class PdfDocumentTest {
    private Context context;
    @Before public void setup() { context = RuntimeEnvironment.getApplication(); PDFBoxResourceLoader.init(context); }
    static File fixture(Context context, String name, String password, boolean extract, boolean text) throws Exception {
        PDFBoxResourceLoader.init(context);
        File file = new File(context.getCacheDir(), name);
        try (PDDocument document = new PDDocument()) {
            for (int i = 0; i < 3; i++) {
                PDPage page = new PDPage(); document.addPage(page);
                try (PDPageContentStream content = new PDPageContentStream(document, page)) {
                    content.setNonStrokingColor(0, 0, 0);
                    content.addRect(20, 20, 50, 50); content.fill();
                    if (text) { content.beginText(); content.setFont(PDType1Font.HELVETICA, 14); content.newLineAtOffset(40, 700); content.showText("Hello page " + (i + 1)); content.endText(); }
                }
            }
            if (password != null) {
                AccessPermission permissions = new AccessPermission(); permissions.setCanExtractContent(extract);
                StandardProtectionPolicy protection = new StandardProtectionPolicy("owner-test-only", password, permissions);
                protection.setEncryptionKeyLength(128); document.protect(protection);
            }
            document.save(file);
        }
        return file;
    }
    @Test public void rendersOriginalPagesAndMapsExtractedTextToPageGeometry() throws Exception {
        File file = fixture(context, "text.pdf", null, true, true);
        try (PdfDocument pdf = new PdfDocument(context, file, null)) {
            assertEquals(3, pdf.pageCount); assertTrue(pdf.mayExtract);
            PdfDocument.Page page = pdf.render(1, 600);
            assertTrue(page.text.contains("Hello page 2")); assertEquals(page.text.length(), page.boxes.size());
            assertTrue(page.boxes.stream().anyMatch(b -> b.width() > 0 && b.top >= 0));
            assertTrue(page.bitmap.getWidth() >= 400); assertTrue(page.bitmap.getHeight() > 0);
            page.bitmap.recycle();
        }
    }
    @Test public void rotatedPagesKeepTextGeometryOnRenderedGlyphs() throws Exception {
        for(int rotation:new int[]{0,90,180,270}) {
            File file=fixture(context,"rotate-base.pdf",null,true,true), rotated=new File(context.getCacheDir(),"rotate-"+rotation+".pdf");
            try(PDDocument doc=PDDocument.load(file)){doc.getPage(0).setRotation(rotation);doc.save(rotated);}
            try(PdfDocument pdf=new PdfDocument(context,rotated,null)){
                PdfDocument.Page page=pdf.render(0,600);
                android.graphics.RectF box=page.boxes.get(0);
                float sx=page.bitmap.getWidth()/page.width,sy=page.bitmap.getHeight()/page.height;
                assertTrue(box.width()>0&&box.height()>0);
                boolean ink=false;
                for(int y=Math.max(0,(int)(box.top*sy)-3);y<Math.min(page.bitmap.getHeight(),(int)(box.bottom*sy)+3);y++)
                    for(int x=Math.max(0,(int)(box.left*sx)-3);x<Math.min(page.bitmap.getWidth(),(int)(box.right*sx)+3);x++)
                        if(Color.red(page.bitmap.getPixel(x,y))<100)ink=true;
                assertTrue("Text box missed the rendered glyph at rotation "+rotation,ink);page.bitmap.recycle();
            }
        }
    }
    @Test public void passwordRetryAndReopenDoNotCreateDecryptedDiskCopies() throws Exception {
        File file = fixture(context, "password.pdf", "reader-test-only", true, true);
        PdfDocument.validate(context, file);
        assertThrows(InvalidPasswordException.class, () -> new PdfDocument(context, file, "wrong"));
        try (PdfDocument pdf = new PdfDocument(context, file, "reader-test-only")) { assertTrue(pdf.text(0).value.contains("Hello")); }
        assertThrows(InvalidPasswordException.class, () -> new PdfDocument(context, file, null));
        assertTrue(new String(java.nio.file.Files.readAllBytes(file.toPath()), java.nio.charset.StandardCharsets.ISO_8859_1).contains("/Encrypt"));
    }
    @Test public void scannedAndProtectedPagesRemainReadableWithoutTextExtraction() throws Exception {
        for (boolean scan : new boolean[]{false, true}) {
            File file = fixture(context, "restricted-" + scan + ".pdf", scan ? null : "reader-test-only", false, !scan);
            try (PdfDocument pdf = new PdfDocument(context, file, scan ? null : "reader-test-only")) {
                assertEquals("", pdf.text(0).value);
                PdfDocument.Page page = pdf.render(0, 500); assertNotNull(page.bitmap); page.bitmap.recycle();
            }
        }
    }
    @Test public void extractingIndividualPagesNeverIncludesAnotherPageOrChangesThePageTree() throws Exception {
        File file=fixture(context,"single-page-extraction.pdf",null,true,true);
        try(PdfDocument pdf=new PdfDocument(context,file,null)) {
            for(int page:new int[]{2,0,1,2}) {
                PdfDocument.Text text=pdf.text(page);
                assertEquals(text.value,pdf.searchText(page));
                assertTrue(text.value.contains("Hello page "+(page+1)));
                for(int other=0;other<3;other++)if(other!=page)assertFalse(text.value.contains("Hello page "+(other+1)));
                assertEquals(text.value.length(),text.boxes.size());
                assertTrue(text.boxes.stream().anyMatch(box->box.width()>0));
            }
            PdfDocument.Page rendered=pdf.render(2,600);
            assertTrue(rendered.text.contains("Hello page 3"));rendered.bitmap.recycle();
        }
        try(PDDocument original=PDDocument.load(file)){assertEquals(3,original.getNumberOfPages());}
    }

    @Test public void cancelledPageExtractionCannotCachePartialTextAndTheNextQueryStillWorks() throws Exception {
        File file=fixture(context,"cancel-extraction.pdf",null,true,true);
        try(PdfDocument pdf=new PdfDocument(context,file,null)) {
            java.util.concurrent.atomic.AtomicInteger checkpoints=new java.util.concurrent.atomic.AtomicInteger();
            assertThrows(java.util.concurrent.CancellationException.class,
                    () -> pdf.searchText(0, () -> checkpoints.incrementAndGet() > 3));
            assertTrue(checkpoints.get() > 3);
            String complete=pdf.searchText(0);
            assertTrue(complete.contains("Hello page 1"));
            assertEquals(pdf.text(0).value,complete);
            // Even a cache hit must honor a newer cancellation request.
            assertThrows(java.util.concurrent.CancellationException.class, () -> pdf.searchText(0, () -> true));
            assertEquals(complete,pdf.searchText(0));
        }
    }
    @Test public void repeatedQueriesReuseSessionTextAndMemoryReclamationPreservesSearchAndGeometry() throws Exception {
        File file=fixture(context,"cached-search.pdf","reader-test-only",true,true);
        try(PdfDocument pdf=new PdfDocument(context,file,"reader-test-only")) {
            String first=pdf.searchText(1);
            assertSame(first,pdf.searchText(1));
            pdf.clearSearchCache();
            String afterPressure=pdf.searchText(1);
            assertNotSame(first,afterPressure);assertEquals(first,afterPressure);
            PdfDocument.Text text=pdf.text(1);
            assertEquals(afterPressure,text.value);assertEquals(text.value.length(),text.boxes.size());
            assertSame(text.value,pdf.searchText(1));
        }
        // Closing the cached session still leaves only the password-protected source.
        assertThrows(InvalidPasswordException.class,() -> new PdfDocument(context,file,null));
    }
    @Test public void cachedSearchRespectsPasswordAndExtractionPermissionsForRc4AndAes() throws Exception {
        File source=fixture(context,"encryption-base.pdf",null,true,true);
        for(int[] algorithm:new int[][]{{40,0},{128,0},{128,1},{256,1}})for(boolean extract:new boolean[]{true,false}) {
            File protectedFile=new File(context.getCacheDir(),"encryption-"+algorithm[0]+"-"+algorithm[1]+"-"+extract+".pdf");
            try(PDDocument document=PDDocument.load(source)) {
                AccessPermission permission=new AccessPermission();permission.setCanExtractContent(extract);
                StandardProtectionPolicy policy=new StandardProtectionPolicy("owner-test-only","reader-test-only",permission);
                policy.setEncryptionKeyLength(algorithm[0]);policy.setPreferAES(algorithm[1]==1);
                document.protect(policy);document.save(protectedFile);
            }
            PdfDocument.validate(context,protectedFile);
            assertThrows(InvalidPasswordException.class,() -> new PdfDocument(context,protectedFile,"wrong"));
            try(PdfDocument pdf=new PdfDocument(context,protectedFile,"reader-test-only")) {
                assertEquals(extract,pdf.mayExtract);
                String text=pdf.searchText(0);
                if(extract)assertTrue(text.contains("Hello page 1"));else assertEquals("",text);
                assertEquals(text,pdf.searchText(0));
                pdf.clearSearchCache();assertEquals(text,pdf.searchText(0));
            }
            assertThrows(InvalidPasswordException.class,() -> new PdfDocument(context,protectedFile,null));
        }
    }
}
