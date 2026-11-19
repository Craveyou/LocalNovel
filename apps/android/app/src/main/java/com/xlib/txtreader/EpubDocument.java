package com.xlib.txtreader;

import android.content.Context;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.StringReader;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Bounded offline EPUB 2/3 reflow subset. Resources remain in the original ZIP. */
final class EpubDocument extends ReflowDocument {
    static final int MAX_ENTRY = 16 * 1024 * 1024;
    private final ZipFile zip;
    private final Map<String, String> entities = new HashMap<>();
    EpubDocument(Context context, File file) throws Exception {
        if (file.length() > PdfDocument.MAX_FILE_BYTES) throw new IOException("EPUB 超过 256 MiB");
        zip = new ZipFile(file);
        try {
            String map;
            try (java.io.InputStream stream = context.getAssets().open("xhtml-entities.tsv")) { map = new String(readLimited(stream), StandardCharsets.UTF_8); }
            for (String line : map.split("\n")) { String[] parts = line.split("\t"); if (parts.length == 2) entities.put(parts[0], parts[1]); }
            long total = 0; int count = 0;
            Enumeration<? extends ZipEntry> entries = zip.entries();
            java.util.HashSet<String> names = new java.util.HashSet<>();
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                if (++count > 10_000)throw new IOException("EPUB 资源过多");
                if (entry.isDirectory()) continue;
                if ( !DocumentLocator.safeResource(entry.getName()) || !names.add(entry.getName())) throw new IOException("EPUB 资源路径无效或资源过多");
                if (entry.getSize() < 0 || entry.getSize() > MAX_ENTRY || (total += entry.getSize()) > 256L * 1024 * 1024
                        || (entry.getCompressedSize() > 0 && entry.getSize() / entry.getCompressedSize() > 1000)) throw new IOException("EPUB 解包资源超过支持限额");
            }
            if (!"application/epub+zip".equals(new String(read("mimetype"), StandardCharsets.US_ASCII).trim())) throw new IOException("不是 EPUB 包");
            if (zip.getEntry("META-INF/encryption.xml") != null) {
                Document encryption = xml(read("META-INF/encryption.xml"));
                if (encryption.getElementsByTagNameNS("*", "EncryptedData").getLength() > 0) throw new IOException("暂不支持 DRM 或加密 EPUB 资源");
            }
            Document container = xml(read("META-INF/container.xml"));
            Element root = first(container, "rootfile"); if (root == null) throw new IOException("缺少 EPUB 包入口");
            String opf = resolve("", root.getAttribute("full-path"));
            Document packageDoc = xml(read(opf));
            Map<String, Element> manifest = new HashMap<>(); NodeList items = packageDoc.getElementsByTagNameNS("*", "item");
            String nav = null, ncx = null;
            for (int i = 0; i < items.getLength(); i++) {
                Element item = (Element) items.item(i);
                if(item.getAttribute("id").isEmpty()||manifest.put(item.getAttribute("id"),item)!=null)throw new IOException("EPUB 资源清单重复或缺少标识");
                if (java.util.Arrays.asList(item.getAttribute("properties").split("\\s+")).contains("nav")) nav = resolve(opf, item.getAttribute("href"));
                if ("application/x-dtbncx+xml".equals(item.getAttribute("media-type"))) ncx = resolve(opf, item.getAttribute("href"));
            }
            NodeList metadata = packageDoc.getElementsByTagNameNS("*", "meta");
            for (int i = 0; i < metadata.getLength(); i++) {
                Element meta = (Element) metadata.item(i);
                if ((meta.getAttribute("property").contains("rendition:layout") && meta.getTextContent().contains("pre-paginated"))
                        || (meta.getAttribute("name").equals("fixed-layout") && meta.getAttribute("content").equals("true"))) throw new IOException("暂不支持固定版式 EPUB");
            }
            long decodedBytes = 0;
            NodeList spine = packageDoc.getElementsByTagNameNS("*", "itemref");
            for (int i = 0; i < spine.getLength(); i++) {
                Element reference = (Element) spine.item(i), item = manifest.get(reference.getAttribute("idref"));
                if ("no".equals(reference.getAttribute("linear"))) continue;
                if (item == null || !"application/xhtml+xml".equals(item.getAttribute("media-type"))) throw new IOException("正文资源不支持或缺失");
                String path = resolve(opf, item.getAttribute("href"));
                for (Chapter existing : chapters) if (existing.resource.equals(path)) throw new IOException("正文清单包含重复资源");
                Chapter chapter = chapter(path);
                decodedBytes += chapter.text.getBytes(StandardCharsets.UTF_8).length + chapter.html.getBytes(StandardCharsets.UTF_8).length;
                if(decodedBytes>64L*1024*1024)throw new IOException("EPUB 正文超过 64 MiB 内存限额");
                chapters.add(chapter);
            }
            if (chapters.isEmpty()) throw new IOException("EPUB 没有可阅读正文");
            if (nav != null) loadNav(nav); else if (ncx != null) loadNcx(ncx);
        } catch (Exception error) { zip.close(); throw error; }
    }
    private static Element first(Document doc, String name) {
        NodeList list = doc.getElementsByTagNameNS("*", name); return list.getLength() == 0 ? null : (Element) list.item(0);
    }
    byte[] read(String path) throws IOException {
        ZipEntry entry = zip.getEntry(path); if (entry == null || entry.isDirectory()) throw new IOException("EPUB 缺少资源");
        try (java.io.InputStream input = zip.getInputStream(entry)) { return readLimited(input); }
    }
    private static byte[] readLimited(java.io.InputStream input) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] bytes = new byte[32 * 1024]; int read;
        while ((read = input.read(bytes)) != -1) { if (out.size() + read > MAX_ENTRY) throw new IOException("资源过大"); out.write(bytes, 0, read); }
        return out.toByteArray();
    }
    private Document xml(byte[] bytes) throws Exception {
        String source = StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString();
        java.util.regex.Matcher encoding=java.util.regex.Pattern.compile("(?i)<\\?xml[^>]*encoding\\s*=\\s*[\"\']([^\"\']+)").matcher(source);
        if(encoding.find()&&!encoding.group(1).equalsIgnoreCase("UTF-8"))throw new IOException("暂只支持 UTF-8 EPUB 正文");
        if (java.util.regex.Pattern.compile("(?i)<!ENTITY").matcher(source).find()) throw new IOException("EPUB 不允许自定义实体");
        source = source.replaceAll("(?is)<!DOCTYPE[^>]*>", "");
        java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("&([A-Za-z][A-Za-z0-9]+);").matcher(source);
        StringBuffer escaped = new StringBuffer();
        while (matcher.find()) {
            String code = entities.get(matcher.group(1));
            matcher.appendReplacement(escaped, java.util.regex.Matcher.quoteReplacement(code == null ? matcher.group() : "&#" + code + ";"));
        }
        matcher.appendTail(escaped);
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance(); factory.setNamespaceAware(true);
        factory.setExpandEntityReferences(false);
        javax.xml.parsers.DocumentBuilder builder = factory.newDocumentBuilder();
        builder.setEntityResolver((publicId, systemId) -> new InputSource(new StringReader("")));
        Document result=builder.parse(new InputSource(new StringReader(escaped.toString())));
        checkTree(result,0,new int[]{0});return result;
    }
    private static void checkTree(Node node,int depth,int[] count)throws IOException{
        if(depth>128||++count[0]>200_000)throw new IOException("EPUB 正文结构超出支持限额");
        for(Node child=node.getFirstChild();child!=null;child=child.getNextSibling())checkTree(child,depth+1,count);
    }
    static String resolve(String base, String href) throws Exception {
        URI origin = new URI("https://book.xlib.invalid/" + base);
        URI target = origin.resolve(href).normalize();
        if (!"book.xlib.invalid".equals(target.getHost()) || !"https".equals(target.getScheme()) || target.getRawQuery() != null) throw new IOException("不支持外部资源");
        String path = URLDecoder.decode(target.getRawPath().substring(1).replace("+", "%2B"), "UTF-8");
        if (!DocumentLocator.safeResource(path)) throw new IOException("资源路径越界");
        return path;
    }
    private Chapter chapter(String path) throws Exception {
        Document doc = xml(read(path)); Element body = first(doc, "body"); if (body == null) throw new IOException("正文缺少 body");
        sanitize(body);
        NodeList images=body.getElementsByTagNameNS("*","img");
        for(int i=0;i<images.getLength();i++){
            String src=((Element)images.item(i)).getAttribute("src");
            if(src.startsWith("data:"))continue;
            String image=resolve(path,src);if(zip.getEntry(image)==null)throw new IOException("EPUB 图片资源缺失");
        }
        StringBuilder text = new StringBuilder(); Map<String, Integer> anchors = new HashMap<>(); collect(body, text, anchors);
        StringBuilder html=new StringBuilder();serialize(body,html);
        StringBuilder styles = new StringBuilder(); NodeList links = doc.getElementsByTagNameNS("*", "link");
        for (int i=0;i<links.getLength();i++) {
            Element link=(Element)links.item(i);
            if ("stylesheet".equals(link.getAttribute("rel"))) {
                String css = resolve(path, link.getAttribute("href"));
                read(css); styles.append("<link rel=\"stylesheet\" href=\"/").append(css.replace("&", "&amp;").replace("\"", "&quot;")).append("\">");
            }
        }
        NodeList inline = doc.getElementsByTagNameNS("*", "style");
        for (int i=0;i<inline.getLength();i++) styles.append("<style>").append(inline.item(i).getTextContent().replaceAll("(?i)</style", "")).append("</style>");
        return new Chapter(path, styles + html.toString(), text.toString(), anchors);
    }
    /** Android's platform HTML transformer adds whitespace and escapes surrogate halves separately. */
    private static void serialize(Node node,StringBuilder out) {
        if(node.getNodeType()==Node.TEXT_NODE||node.getNodeType()==Node.CDATA_SECTION_NODE){out.append(escape(node.getNodeValue()));return;}
        if(!(node instanceof Element))return;
        Element element=(Element)node;String tag=element.getLocalName()==null?element.getTagName():element.getLocalName();
        out.append('<').append(tag);
        for(int i=0;i<element.getAttributes().getLength();i++){
            Node attr=element.getAttributes().item(i);
            if(attr.getNodeName().startsWith("xmlns"))continue;
            out.append(' ').append(attr.getNodeName()).append("=\"").append(escape(attr.getNodeValue()).replace("\"","&quot;")).append('"');
        }
        out.append('>');
        if("style".equalsIgnoreCase(tag))out.append(element.getTextContent().replaceAll("(?i)</style",""));
        else for(Node child=node.getFirstChild();child!=null;child=child.getNextSibling())serialize(child,out);
        if(!java.util.Arrays.asList("area","base","br","col","embed","hr","img","input","link","meta","param","source","track","wbr").contains(tag.toLowerCase(java.util.Locale.ROOT)))out.append("</").append(tag).append('>');
    }
    private static String escape(String text){return text.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;");}
    private static void sanitize(Element root) {
        for (int i = root.getAttributes().getLength() - 1; i >= 0; i--) {
            String name = root.getAttributes().item(i).getNodeName().toLowerCase(java.util.Locale.ROOT);
            if (name.startsWith("on") || name.equals("srcdoc") || name.equals("formaction") || name.equals("xmlns")) root.removeAttribute(root.getAttributes().item(i).getNodeName());
        }
        List<Node> remove = new ArrayList<>();
        for (Node child = root.getFirstChild(); child != null; child = child.getNextSibling()) if (child instanceof Element) {
            Element element = (Element) child;
            String tag = element.getLocalName() == null ? element.getTagName() : element.getLocalName();
            if (java.util.Arrays.asList("script", "iframe", "object", "embed", "form", "input", "button", "audio", "video", "base", "meta").contains(tag.toLowerCase(java.util.Locale.ROOT))) remove.add(child);
            else sanitize(element);
        }
        for (Node child : remove) root.removeChild(child);
    }
    private static void collect(Node node, StringBuilder text, Map<String, Integer> anchors) {
        if (node instanceof Element) {
            Element e = (Element) node;
            if ("style".equalsIgnoreCase(e.getLocalName())) return;
            if (e.hasAttribute("id")) { if (!anchors.containsKey(e.getAttribute("id"))) anchors.put(e.getAttribute("id"), text.length()); }
        }
        if (node.getNodeType() == Node.TEXT_NODE || node.getNodeType() == Node.CDATA_SECTION_NODE) text.append(node.getNodeValue());
        for (Node child=node.getFirstChild();child!=null;child=child.getNextSibling()) collect(child,text,anchors);
    }
    private void addToc(String label, String base, String href) throws Exception {
        String resource = resolve(base, href), fragment = new URI(href).getFragment();
        for (int i=0;i<chapters.size();i++) if (chapters.get(i).resource.equals(resource)) {
            if(fragment!=null&&!chapters.get(i).anchors.containsKey(fragment))return;
            int offset = fragment == null ? 0 : chapters.get(i).anchors.get(fragment);
            toc.add(new Toc(label.trim(), i, offset)); return;
        }
    }
    private void loadNav(String path) throws Exception {
        Document doc=xml(read(path)); NodeList navs=doc.getElementsByTagNameNS("*","nav");
        for(int i=0;i<navs.getLength();i++) {
            Element nav=(Element)navs.item(i); String type=nav.getAttributeNS("http://www.idpf.org/2007/ops","type");
            if (!java.util.Arrays.asList(type.split("\\s+")).contains("toc")) continue;
            NodeList links=nav.getElementsByTagNameNS("*","a");
            for(int j=0;j<links.getLength();j++) { Element a=(Element)links.item(j); try { addToc(a.getTextContent(),path,a.getAttribute("href")); } catch(Exception ignored) { } }
            return;
        }
    }
    private void loadNcx(String path) throws Exception {
        NodeList points=xml(read(path)).getElementsByTagNameNS("*","navPoint");
        for(int i=0;i<points.getLength();i++) {
            Element p=(Element)points.item(i); NodeList content=p.getElementsByTagNameNS("*","content"), labels=p.getElementsByTagNameNS("*","text");
            if(content.getLength()>0 && labels.getLength()>0) try { addToc(labels.item(0).getTextContent(),path,((Element)content.item(0)).getAttribute("src")); } catch(Exception ignored) { }
        }
    }
    DocumentLocator locator(int chapter, int offset) {
        Chapter c=chapters.get(chapter); return DocumentLocator.epub(c.resource,chapter,chapters.size(),ReaderTextSelection.boundary(c.text,offset),c.text.length());
    }
    boolean valid(DocumentLocator locator) {
        return locator != null && "epub".equals(locator.format) && locator.spineCount == chapters.size() && locator.spineIndex < chapters.size()
                && ReaderTextSelection.boundary(chapters.get(locator.spineIndex).text,locator.textOffset)==locator.textOffset
                && chapters.get(locator.spineIndex).resource.equals(locator.resource) && chapters.get(locator.spineIndex).text.length() == locator.textLength;
    }
    @Override public void close() throws IOException { zip.close(); }
}
