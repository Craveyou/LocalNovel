package com.xlib.txtreader;

import static org.junit.Assert.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.*;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class DocumentFormatsTest {
    @Rule public TemporaryFolder folder=new TemporaryFolder();
    private File file(byte[] bytes)throws Exception{File file=folder.newFile();Files.write(file.toPath(),bytes);return file;}
    private File zip(Map<String,String> resources)throws Exception {File file=folder.newFile();try(ZipOutputStream out=new ZipOutputStream(new FileOutputStream(file))){for(Map.Entry<String,String> e:resources.entrySet()){out.putNextEntry(new ZipEntry(e.getKey()));out.write(e.getValue().getBytes(StandardCharsets.UTF_8));out.closeEntry();}}return file;}
    @Test public void epubWinsOverImagesButBrokenEpubNeverFallsThroughToComicOrText()throws Exception {
        File epub=zip(Map.of("mimetype","application/epub+zip","META-INF/container.xml","container","1.png","image"));
        assertEquals("epub",DocumentFormats.detect(epub,"Book.EPUB"));
        assertEquals("epub",DocumentFormats.detect(epub,"unknown.bin"));
        File cbz=zip(Map.of("1.png","image"));assertEquals("cbz",DocumentFormats.detect(cbz,"Book.CBZ"));assertEquals("cbz",DocumentFormats.detect(cbz,"archive.zip"));
        assertThrows(IOException.class,()->DocumentFormats.detect(cbz,"broken.EPUB"));
        assertThrows(IOException.class,()->DocumentFormats.detect(epub,"wrong.cbz"));
    }
    @Test public void ordinaryZipOfficeAndUnknownBinaryNeverBecomeTextOrPdf()throws Exception {
        for(File file:List.of(zip(Map.of("README.txt","text")),zip(Map.of("[Content_Types].xml","office","word/media/1.png","image")),file(new byte[]{0,1,2,3,4}),file(new byte[]{'P','K',3,4,1}))){assertThrows(IOException.class,()->DocumentFormats.detect(file,"unknown.dat"));}
        File text=file("正文\nhello".getBytes(StandardCharsets.UTF_8));
        for(String name:List.of("book.pdf","book.epub","book.mobi","book.azw","book.azw3","book.kfx","book.cbr","book.docx"))assertThrows(IOException.class,()->DocumentFormats.detect(text,name));
    }
    @Test public void legacyEncodingsAndPdfRemainSupportedAndConflictingExtensionsFail()throws Exception {
        for(String encoding:List.of("UTF-8","UTF-16LE","UTF-16BE","GB18030")){
            byte[] text="中文小说\nABC 😀".getBytes(encoding);if(encoding.startsWith("UTF-16")){byte[] bom=new byte[text.length+2];bom[0]=(byte)(encoding.endsWith("LE")?255:254);bom[1]=(byte)(encoding.endsWith("LE")?254:255);System.arraycopy(text,0,bom,2,text.length);text=bom;}
            assertEquals("txt",DocumentFormats.detect(file(text),"Book.TXT"));
        }
        File pdf=file("%PDF-1.4".getBytes(StandardCharsets.US_ASCII));assertEquals("pdf",DocumentFormats.detect(pdf,"Book.PDF"));assertThrows(IOException.class,()->DocumentFormats.detect(pdf,"Book.txt"));
    }
    @Test public void rarAndKindleAreExplicitlyIdentifiedAndDoNotReachExistingReaders()throws Exception {
        for(byte[] signature:new byte[][]{{82,97,114,33,26,7,0},{82,97,114,33,26,7,1,0}})assertEquals("cbr",DocumentFormats.detect(file(signature),"book.CBR"));
        byte[] mobi=KindleTestFiles.single(6);
        File source=file(mobi);for(String name:List.of("a.MOBI","b.azw","c.AZW3","unknown.bin"))assertEquals("kindle",DocumentFormats.detect(source,name));
        mobi[KindleTestFiles.recordOffset(mobi,0)+13]=2;File drm=file(mobi);assertTrue(assertThrows(IOException.class,()->DocumentFormats.detect(drm,"book.azw")).getMessage().contains("DRM"));
        assertTrue(DocumentFormats.readable("cbz"));assertTrue(DocumentFormats.readable("cbr"));
        assertTrue(DocumentFormats.readable("kindle"));
        for(String format:List.of("future")){assertFalse(DocumentFormats.readable(format));assertThrows(IOException.class,()->DocumentFormats.validate(null,source,format));}
    }
    @Test public void binaryBeyondTheEncodingSampleAndCancelledValidationReject()throws Exception {
        byte[] bytes=new byte[10000];Arrays.fill(bytes,(byte)'a');bytes[9999]=0;File binary=file(bytes);assertThrows(IOException.class,()->DocumentFormats.detect(binary,"unknown.bin"));
        assertThrows(IOException.class,()->DocumentFormats.detect(binary,"book.txt",()->true));
    }
}
