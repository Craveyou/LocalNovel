package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.content.Context;
import org.robolectric.RuntimeEnvironment;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

@RunWith(RobolectricTestRunner.class) @Config(sdk={23,35})
public class EpubDocumentTest {
    final Context context=RuntimeEnvironment.getApplication();
    private void entry(ZipOutputStream zip,String path,String text)throws Exception{zip.putNextEntry(new ZipEntry(path));zip.write(text.getBytes(StandardCharsets.UTF_8));zip.closeEntry();}
    File sample(String extra,String metadata)throws Exception{
        File file=File.createTempFile("sample", ".epub",context.getCacheDir());
        try(ZipOutputStream zip=new ZipOutputStream(new FileOutputStream(file))){
            entry(zip,"mimetype","application/epub+zip");
            entry(zip,"META-INF/container.xml","<container xmlns='urn:oasis:names:tc:opendocument:xmlns:container'><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>");
            entry(zip,"OPS/book.opf","<package xmlns='http://www.idpf.org/2007/opf' version='3.0'><metadata>"+metadata+"</metadata><manifest><item id='z' href='z.xhtml' media-type='application/xhtml+xml'/><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/></manifest><spine><itemref idref='z'/><itemref idref='a'/></spine></package>");
            entry(zip,"OPS/z.xhtml","<html xmlns='http://www.w3.org/1999/xhtml'><head><style>p{color:red}</style></head><body><h1 id='start'>正文👩‍💻</h1><p>A&nbsp;é<span id='later'>继续</span></p><script>bad()</script></body></html>");
            entry(zip,"OPS/a.xhtml","<html xmlns='http://www.w3.org/1999/xhtml'><body>第二章</body></html>");
            entry(zip,"OPS/nav.xhtml","<html xmlns='http://www.w3.org/1999/xhtml' xmlns:epub='http://www.idpf.org/2007/ops'><body><nav epub:type='toc'><a href='z.xhtml#later'>稍后</a><a href='z.xhtml#missing'>无效</a><a href='a.xhtml'>下一章</a></nav></body></html>");
            if(extra!=null)entry(zip,extra,"invalid");
        }
        return file;
    }
    @Test public void spineUnicodeEntitiesAnchorsAndTocAreStable()throws Exception{
        try(EpubDocument doc=new EpubDocument(context,sample(null,""))){
            assertEquals("OPS/z.xhtml",doc.chapters.get(0).resource);
            assertEquals("正文👩‍💻A\u00a0é继续",doc.chapters.get(0).text);
            assertFalse(doc.chapters.get(0).html.contains("bad()"));
            assertEquals(2,doc.toc.size());
            int offset=doc.chapters.get(0).text.indexOf("继续");
            assertEquals(offset,doc.toc.get(0).offset);
            assertTrue(doc.valid(doc.locator(0,offset)));
            assertFalse(doc.valid(DocumentLocator.epub("OPS/z.xhtml",0,2,offset,999)));
            DocumentSearch search=new DocumentSearch("继续",0,0);
            assertEquals(offset, search.next(new DocumentSearch.Source(){public int units(){return doc.chapters.size();}public String text(int i){return doc.chapters.get(i).text;}public DocumentLocator locator(int i,int o){return doc.locator(i,o);}}).get(0).locator.textOffset);
        }
    }
    @Test public void traversalAndUnsupportedFixedLayoutAreRejected()throws Exception{
        assertThrows(Exception.class,()->new EpubDocument(context,sample("../outside","")));
        assertThrows(Exception.class,()->new EpubDocument(context,sample(null,"<meta property='rendition:layout'>pre-paginated</meta>")));
        assertEquals("OPS/image.png",EpubDocument.resolve("OPS/Text/a.xhtml","../image.png"));
        assertThrows(Exception.class,()->EpubDocument.resolve("OPS/a.xhtml","../../outside"));
        assertThrows(Exception.class,()->EpubDocument.resolve("OPS/a.xhtml","https://example.com/remote.png"));
    }
}
