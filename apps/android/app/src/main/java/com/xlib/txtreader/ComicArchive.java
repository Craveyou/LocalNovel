package com.xlib.txtreader;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.zip.CRC32;
import java.util.zip.Inflater;
import java.util.zip.InflaterInputStream;

/** Bounded ZIP reader, including CP437/Unicode paths on API 23. Never extracts archive paths. */
final class ComicArchive implements AutoCloseable {
    static final long MAX_SOURCE = 1024L * 1024 * 1024;
    static final long MAX_ENTRY = 128L * 1024 * 1024;
    static final long MAX_TOTAL = 4L * 1024 * 1024 * 1024;
    interface Cancellation { boolean cancelled(); }
    static final Cancellation NEVER = () -> false;
    static final class Entry {
        final String name;
        final long size, packed, crc, offset;
        final int method, flags;
        final byte[] rawName;
        Entry(String name, long size, long packed, long crc, long offset, int method, int flags, byte[] rawName) {
            this.name=name; this.size=size; this.packed=packed; this.crc=crc; this.offset=offset;
            this.method=method; this.flags=flags; this.rawName=rawName;
        }
    }
    private final RandomAccessFile file;
    final List<Entry> entries = new ArrayList<>();
    private long central;

    ComicArchive(File source, Cancellation cancel) throws IOException {
        if (source.length()>MAX_SOURCE) throw new IOException("漫画包超过 1 GiB");
        file = new RandomAccessFile(source,"r");
        try { readDirectory(cancel); } catch(IOException | RuntimeException error) { file.close(); throw error; }
    }
    private void readDirectory(Cancellation cancel) throws IOException {
        long end=-1, length=file.length();
        byte[] tail=new byte[(int)Math.min(length,65557)]; file.seek(length-tail.length); file.readFully(tail);
        for(int i=tail.length-22;i>=0;i--) if(u32(tail,i)==0x06054b50L && i+22+u16(tail,i+20)==tail.length) { end=length-tail.length+i; break; }
        if(end<0)throw new IOException("ZIP 目录损坏或缺失");
        file.seek(end);byte[] header=new byte[22];file.readFully(header);
        int count=u16(header,10); long bytes=u32(header,12);central=u32(header,16);
        if(u16(header,4)!=0||u16(header,6)!=0||u16(header,8)!=count)throw new IOException("暂不支持分卷漫画包");
        if(count==65535||bytes==0xffffffffL||central==0xffffffffL)throw new IOException("当前漫画预览暂不支持 ZIP64");
        if(count>20000||bytes>32L*1024*1024||central+bytes!=end)throw new IOException("ZIP 目录超出限额或已损坏");
        file.seek(central);HashSet<String> names=new HashSet<>();long total=0;
        for(int i=0;i<count;i++) {
            check(cancel);byte[] h=new byte[46];file.readFully(h);
            if(u32(h,0)!=0x02014b50L)throw new IOException("ZIP 目录损坏");
            int flags=u16(h,8),method=u16(h,10),n=u16(h,28),extraLength=u16(h,30),comment=u16(h,32);
            if((flags & (1|64|8192))!=0)throw new IOException("暂不支持加密漫画包");
            if(method!=0&&method!=8)throw new IOException("漫画包使用了暂不支持的压缩方法");
            if(n==0||n>4096||file.getFilePointer()+n+extraLength+comment>central+bytes)throw new IOException("ZIP 文件名或目录无效");
            byte[] raw=new byte[n],extra=new byte[extraLength];file.readFully(raw);file.readFully(extra);file.skipBytes(comment);
            String name=canonical(decodeName(raw,extra,flags));
            if(!names.add(name.endsWith("/")?name.substring(0,name.length()-1):name))throw new IOException("漫画包包含重复路径");
            int host=(u16(h,4)>>>8),mode=(int)(u32(h,38)>>>16)&0170000;
            if(host==3&&mode!=0&&mode!=0100000&&mode!=0040000)throw new IOException("漫画包不允许链接或特殊文件");
            long size=u32(h,24),packed=u32(h,20),offset=u32(h,42);
            if(u16(h,34)!=0||offset==0xffffffffL)throw new IOException("暂不支持分卷或 ZIP64 漫画包");
            if(size>MAX_ENTRY||packed>MAX_ENTRY||(total+=size)>MAX_TOTAL||offset+30>central)throw new IOException("漫画包展开内容超出限额或已损坏");
            if(method==0&&size!=packed)throw new IOException("ZIP 页面长度无效");
            entries.add(new Entry(name,size,packed,u32(h,16),offset,method,flags,raw));
        }
        if(file.getFilePointer()!=central+bytes)throw new IOException("ZIP 目录长度不匹配");
    }
    Entry find(String path) { for(Entry entry:entries)if(entry.name.equals(path))return entry;return null; }
    List<Entry> pages() throws IOException { return pages(entries); }
    static List<Entry> pages(List<Entry> entries) throws IOException {
        List<Entry> result=new ArrayList<>();
        for(Entry e:entries) {
            if(e.name.endsWith("/")||hidden(e.name))continue;
            String lower=e.name.toLowerCase(Locale.ROOT);
            if(lower.matches(".*\\.(jpg|jpeg|png)$"))result.add(e);
            else if(lower.matches(".*\\.(gif|webp|bmp|dib|tiff?|heic|heif|avif|jxl|jp2|j2k|jpf|jpx|jpm|mj2|svg|svgz|ico|cur|apng|psd|psb|tga|dds|pnm|pbm|pgm|ppm|pam|pcx|qoi|jpe|jfif)$"))throw new IOException("漫画页面暂只支持 JPEG/PNG，包内存在其他图片格式");
        }
        if(result.isEmpty())throw new IOException("漫画包中没有 JPEG/PNG 页面");
        if(result.size()>10000)throw new IOException("漫画超过 10000 页");
        // comic-order-v1: ASCII numeric/component comparison, then full Unicode scalar tie-break.
        java.util.Collections.sort(result,(a,b)->comparePaths(a.name,b.name));return result;
    }
    synchronized void copy(Entry entry, OutputStream output, Cancellation cancel) throws IOException {
        check(cancel);file.seek(entry.offset);byte[] h=new byte[30];file.readFully(h);
        if(u32(h,0)!=0x04034b50L||u16(h,6)!=entry.flags||u16(h,8)!=entry.method||u16(h,26)!=entry.rawName.length)throw new IOException("ZIP 页面头与目录不一致");
        byte[] name=new byte[entry.rawName.length];file.readFully(name);
        if(!Arrays.equals(name,entry.rawName))throw new IOException("ZIP 页面名称与目录不一致");
        long data=file.getFilePointer()+u16(h,28);
        if(data+entry.packed>central)throw new IOException("ZIP 页面数据越界");
        file.seek(data);
        InputStream bounded=new InputStream(){
            long remaining=entry.packed;
            @Override public int read()throws IOException {byte[] one=new byte[1];return read(one,0,1)<0?-1:one[0]&255;}
            @Override public int read(byte[] buffer,int start,int length)throws IOException {
                if(length==0)return 0;if(remaining==0)return -1;
                int read=file.read(buffer,start,(int)Math.min(length,remaining));
                if(read<0)throw new IOException("ZIP 页面意外结束");remaining-=read;return read;
            }
        };
        Inflater inflater=entry.method==8?new Inflater(true):null;
        InputStream input=inflater==null?bounded:new InflaterInputStream(bounded,inflater,32768);
        long total=0;CRC32 crc=new CRC32();byte[] buffer=new byte[32768];
        try {
            int read;while((read=input.read(buffer))!=-1){check(cancel);total+=read;if(total>entry.size||total>MAX_ENTRY)throw new IOException("ZIP 实际展开长度超出限额");crc.update(buffer,0,read);output.write(buffer,0,read);}
            if(total!=entry.size||crc.getValue()!=entry.crc||inflater!=null&&inflater.getBytesRead()!=entry.packed)throw new IOException("漫画页面校验失败，原文件可能已损坏");
        } finally {if(inflater!=null)inflater.end();}
    }
    static void check(Cancellation cancel)throws IOException {if(cancel.cancelled()||Thread.currentThread().isInterrupted())throw new IOException("已取消");}
    static String canonical(String path)throws IOException {
        String name=Normalizer.normalize(path,Normalizer.Form.NFC);
        if(name.startsWith("/")||name.contains("\\")||name.contains(":"))throw new IOException("漫画包路径不安全");
        String parts=name.endsWith("/")?name.substring(0,name.length()-1):name;
        for(String part:parts.split("/",-1))if(part.isEmpty()||part.equals(".")||part.equals(".."))throw new IOException("漫画包路径不安全");
        for(int i=0;i<name.length();){int c=name.codePointAt(i);if(Character.isISOControl(c)||c>=0xd800&&c<=0xdfff)throw new IOException("漫画包文件名无效");i+=Character.charCount(c);}
        return name;
    }
    private static String decodeName(byte[] raw,byte[] extra,int flags)throws IOException {
        String base=decode(raw,(flags&2048)!=0?StandardCharsets.UTF_8:Charset.forName("CP437")),unicode=null;
        for(int i=0;i<extra.length;) {
            if(i+4>extra.length)throw new IOException("ZIP 扩展字段损坏");int tag=u16(extra,i),length=u16(extra,i+2);i+=4;
            if(i+length>extra.length)throw new IOException("ZIP 扩展字段越界");
            if(tag==0x7075) {
                if(length<5||extra[i]!=1)throw new IOException("ZIP Unicode 路径字段无效");
                CRC32 crc=new CRC32();crc.update(raw);
                if(u32(extra,i+1)!=crc.getValue())throw new IOException("ZIP Unicode 路径校验失败");
                String value=decode(Arrays.copyOfRange(extra,i+5,i+length),StandardCharsets.UTF_8);
                if(unicode!=null&&!unicode.equals(value))throw new IOException("ZIP Unicode 路径冲突");unicode=value;
            }
            i+=length;
        }
        if((flags&2048)!=0&&unicode!=null&&!base.equals(unicode))throw new IOException("ZIP 文件名编码冲突");
        return unicode==null?base:unicode;
    }
    private static String decode(byte[] raw,Charset charset)throws IOException {
        return charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString();
    }
    private static boolean hidden(String name){for(String part:name.split("/"))if(part.startsWith(".")||part.equals("__MACOSX"))return true;return false;}
    static int comparePaths(String a,String b) {
        String[] x=a.split("/"),y=b.split("/");
        for(int i=0;i<Math.min(x.length,y.length);i++){int n=compareComponent(x[i],y[i]);if(n!=0)return n;}
        if(x.length!=y.length)return Integer.compare(x.length,y.length);return scalarCompare(a,b);
    }
    private static int compareComponent(String a,String b) {
        int i=0,j=0;
        while(i<a.length()&&j<b.length()) {
            int x=a.codePointAt(i),y=b.codePointAt(j);
            int ie=i+Character.charCount(x),je=j+Character.charCount(y);
            while(ie<a.length()&&digit(a.codePointAt(ie))==digit(x))ie+=Character.charCount(a.codePointAt(ie));
            while(je<b.length()&&digit(b.codePointAt(je))==digit(y))je+=Character.charCount(b.codePointAt(je));
            if(digit(x)&&digit(y)) {
                int iz=i,jz=j;while(iz<ie&&a.charAt(iz)=='0')iz++;while(jz<je&&b.charAt(jz)=='0')jz++;
                int n=Integer.compare(ie-iz,je-jz);if(n!=0)return n;
                for(int k=0;k<ie-iz;k++){n=Character.compare(a.charAt(iz+k),b.charAt(jz+k));if(n!=0)return n;}
            } else {
                int li=i,rj=j;
                while(li<ie&&rj<je){int l=a.codePointAt(li),r=b.codePointAt(rj),n=Integer.compare(fold(l),fold(r));if(n!=0)return n;li+=Character.charCount(l);rj+=Character.charCount(r);}
                if(li<ie||rj<je)return li==ie?-1:1;
            }
            i=ie;j=je;
        }
        return Integer.compare(a.length()-i,b.length()-j);
    }
    private static int scalarCompare(String a,String b){int i=0,j=0;while(i<a.length()&&j<b.length()){int x=a.codePointAt(i),y=b.codePointAt(j);if(x!=y)return Integer.compare(x,y);i+=Character.charCount(x);j+=Character.charCount(y);}return Integer.compare(a.length()-i,b.length()-j);}
    private static boolean digit(int c){return c>='0'&&c<='9';}
    private static int fold(int c){return c>='A'&&c<='Z'?c+32:c;}
    private static int u16(byte[] b,int i){return (b[i]&255)|((b[i+1]&255)<<8);}
    private static long u32(byte[] b,int i){return (u16(b,i)&65535L)|((long)u16(b,i+2)<<16);}
    @Override public void close()throws IOException {file.close();}
}
