package com.xlib.txtreader;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.util.*;

/** Policy wrapper around the shared pinned archive core. JNI never extracts named paths. */
final class NativeComicArchive implements AutoCloseable {
    interface Visitor { void entry(int index,byte[] name,long size,boolean directory)throws IOException; }
    static { System.loadLibrary("xlib_archive"); }
    private static native void visit(byte[] path,int wanted,Visitor visitor,ComicArchive.Cancellation cancel,OutputStream output)throws IOException;
    private static void scan(byte[] path,int wanted,Visitor visitor,ComicArchive.Cancellation cancel,OutputStream output)throws IOException {
        try{visit(path,wanted,visitor,cancel,output);}catch(IOException error){
            ComicArchive.check(cancel);
            String message=error.getMessage();
            if(message!=null&&message.matches("(?s).*[^\\x00-\\x7F].*"))throw error;
            throw new IOException("漫画包校验失败：文件可能损坏、加密、分卷或使用暂不支持的压缩方式",error);
        }
    }
    final List<ComicArchive.Entry> entries=new ArrayList<>();
    private final File source;
    private final long length,modified;
    NativeComicArchive(File source,ComicArchive.Cancellation cancel)throws IOException {
        this.source=source;length=source.length();modified=source.lastModified();Set<String> seen=new HashSet<>();
        scan(path(),-1,(index,raw,size,directory)->{
            String name=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString();
            name=ComicArchive.canonical(name);
            if(directory&&!name.endsWith("/"))name+="/";
            String identity=name.endsWith("/")?name.substring(0,name.length()-1):name;
            if(!seen.add(identity))throw new IOException("漫画包包含重复路径");
            entries.add(new ComicArchive.Entry(name,size,0,0,index,0,0,new byte[0]));
        },()->cancel.cancelled()||Thread.currentThread().isInterrupted(),null);
        ComicArchive.check(cancel);
    }
    private byte[] path(){return source.getAbsolutePath().getBytes(StandardCharsets.UTF_8);}
    void copy(ComicArchive.Entry entry,OutputStream output,ComicArchive.Cancellation cancel)throws IOException {
        if(length!=source.length()||modified!=source.lastModified())throw new IOException("原漫画已变化，请重新打开");
        scan(path(),(int)entry.offset,(index,raw,size,directory)->{
            String name=ComicArchive.canonical(StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString());
            if(directory&&!name.endsWith("/"))name+="/";
            if(index>=entries.size()||!entries.get(index).name.equals(name)||entries.get(index).size!=size)throw new IOException("漫画包清单已变化");
        },()->cancel.cancelled()||Thread.currentThread().isInterrupted(),output);
        ComicArchive.check(cancel);
    }
    interface PageValidator {void validate(File file,ComicArchive.Entry entry)throws IOException;}
    /** Decode validation in physical order: solid archives must never restart for every page. */
    void validatePages(List<ComicArchive.Entry> pages,File scratch,PageValidator validator,ComicArchive.Cancellation cancel)throws IOException {
        Set<ComicArchive.Entry> selected=new HashSet<>(pages);
        class PageSink extends OutputStream {
            FileOutputStream stream;ComicArchive.Entry current;
            void finish()throws IOException {if(stream!=null){stream.close();stream=null;ComicArchive.check(cancel);validator.validate(scratch,current);scratch.delete();current=null;}}
            void begin(ComicArchive.Entry entry)throws IOException {finish();if(selected.contains(entry)){ComicPreviewFiles.reserve(scratch.getParentFile(),entry.size);current=entry;stream=new FileOutputStream(scratch);}}
            public void write(int value)throws IOException {if(stream!=null)stream.write(value);}
            public void write(byte[] bytes,int start,int count)throws IOException {if(stream!=null)stream.write(bytes,start,count);}
        }
        if(length!=source.length()||modified!=source.lastModified())throw new IOException("原漫画已变化，请重新打开");
        PageSink sink=new PageSink();int[] visited={0};
        try{
            scan(path(),-2,(index,raw,size,directory)->{
                String name=ComicArchive.canonical(StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString());
                if(directory&&!name.endsWith("/"))name+="/";
                if(index>=entries.size()||!entries.get(index).name.equals(name)||entries.get(index).size!=size)throw new IOException("漫画包清单已变化");
                visited[0]++;sink.begin(entries.get(index));
            },()->cancel.cancelled()||Thread.currentThread().isInterrupted(),sink);
            if(visited[0]!=entries.size())throw new IOException("漫画包清单不完整");
            sink.finish();ComicArchive.check(cancel);
        }finally{if(sink.stream!=null)sink.stream.close();scratch.delete();}
    }
    public void close(){} // Native handles live only for the duration of a cancellable scan/read.
}
