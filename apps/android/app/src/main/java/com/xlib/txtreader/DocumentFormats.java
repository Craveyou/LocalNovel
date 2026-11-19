package com.xlib.txtreader;

import android.content.Context;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

final class DocumentFormats {
    private DocumentFormats() { }
    static final class UnsupportedDocumentException extends IOException {
        UnsupportedDocumentException(String message) { super(message); }
    }
    static String detect(File file, String name) throws IOException {
        return detect(file,name,ComicArchive.NEVER);
    }
    static String detect(File file, String name,ComicArchive.Cancellation cancel) throws IOException {
        ComicArchive.check(cancel);
        byte[] head = new byte[1024];
        int count;
        try (FileInputStream input = new FileInputStream(file)) { count = input.read(head); }
        if (count <= 0) throw new IOException("文件为空");
        String header = new String(head, 0, count, StandardCharsets.ISO_8859_1);
        String lower = name == null ? "" : name.toLowerCase(Locale.ROOT);
        String format;
        if (header.startsWith("%PDF-")) format="pdf";
        else if (header.startsWith("PK\003\004") || header.startsWith("PK\005\006")) {
            try(ComicArchive zip=new ComicArchive(file,cancel)) {
                ComicArchive.Entry mime=zip.find("mimetype");
                boolean epub=false;
                if(mime!=null&&mime.size<=128){java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();zip.copy(mime,out,ComicArchive.NEVER);epub="application/epub+zip".equals(new String(out.toByteArray(),StandardCharsets.US_ASCII).trim());}
                if(epub&&zip.find("META-INF/container.xml")!=null)format="epub";
                else {
                    if(lower.endsWith(".epub")||epub||zip.find("META-INF/container.xml")!=null)throw new UnsupportedDocumentException("EPUB 结构损坏，不能作为漫画或 TXT 打开");
                    if(zip.find("[Content_Types].xml")!=null)throw new UnsupportedDocumentException("暂不支持 Office 文档");
                    zip.pages();format="cbz";
                }
            }
        } else if(header.startsWith("Rar!\032\007\000")||header.startsWith("Rar!\032\007\001\000")) format="cbr";
        else if(count>=68&&header.substring(60,68).equals("BOOKMOBI")) { KindleContainer.inspect(file,cancel);format="kindle"; }
        else {
            if(lower.matches(".*\\.(pdf|epub|cbz|cbr|mobi|azw|azw3|azw4|kfx|zip|rar|docx?|rtf)$"))throw new UnsupportedDocumentException("文件内容与格式不符，或该格式暂不支持");
            validateText(file,cancel);format="txt";
        }
        String suffix=lower.substring(lower.lastIndexOf('.')+1);
        String declared="mobi".equals(suffix)||"azw".equals(suffix)||"azw3".equals(suffix)?"kindle":suffix;
        if(java.util.Arrays.asList("txt","pdf","epub","cbz","cbr","kindle").contains(declared)&&!declared.equals(format))
            throw new UnsupportedDocumentException("文件后缀与实际内容不一致，请确认文件格式");
        if(lower.endsWith(".azw4")||lower.endsWith(".kfx"))throw new UnsupportedDocumentException("暂不支持 KFX 或固定版式 Kindle 文档");
        return format;
    }
    static void validate(Context context, File file, String format) throws Exception {validate(context,file,format,ComicArchive.NEVER);}
    static void validate(Context context, File file, String format,ComicArchive.Cancellation cancelled) throws Exception {
        if ("pdf".equals(format)) PdfDocument.validate(context, file);
        else if ("epub".equals(format)) try (EpubDocument ignored = new EpubDocument(context, file)) { }
        else if("cbz".equals(format)||"cbr".equals(format)){
            File root=new File(context.getCacheDir(),"comic-validation");if(!root.exists()&&!root.mkdirs())throw new IOException("无法创建漫画校验缓存");
            File directory=File.createTempFile("validate-","",root);if(!directory.delete()||!directory.mkdir())throw new IOException("无法创建漫画校验缓存");
            try(ComicDocument document=new ComicDocument(file,directory,cancelled)){document.validate(cancelled);}finally{File[] files=directory.listFiles();if(files!=null)for(File scratch:files)scratch.delete();directory.delete();}
        }
        else if("kindle".equals(format)){
            try(KindleDocument ignored=new KindleDocument(context,file,cancelled)){}
        }
        else if(!"txt".equals(format))throw new UnsupportedDocumentException("暂不支持此文档格式");
    }
    static boolean readable(String format) { return "txt".equals(format)||"pdf".equals(format)||"epub".equals(format)||"cbz".equals(format)||"cbr".equals(format)||"kindle".equals(format); }
    private static void validateText(File file,ComicArchive.Cancellation cancel)throws IOException {
        Charset charset=Charset.forName(TextFileUtils.detectEncoding(file));
        try(InputStreamReader reader=new InputStreamReader(new FileInputStream(file),charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT))) {
            char[] buffer=new char[32768];int read;
            while((read=reader.read(buffer))!=-1){ComicArchive.check(cancel);for(int i=0;i<read;i++){char c=buffer[i];if(Character.isISOControl(c)&&c!='\n'&&c!='\r'&&c!='\t'&&c!='\f')throw new UnsupportedDocumentException("文件不是可阅读的纯文本");}}
        } catch(java.nio.charset.CharacterCodingException error){throw new UnsupportedDocumentException("文件不是受支持编码的纯文本");}
    }
}
