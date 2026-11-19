package com.xlib.txtreader;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.List;

/** Bounded original-image rendering, with the shared RAR core and comic-order-v1 manifest. */
final class ComicDocument implements AutoCloseable {
    static final long MAX_PIXELS=100_000_000L, CACHE_BYTES=64L*1024*1024;
    static final int DECODE_BYTES=16*1024*1024;
    private final ComicArchive archive;
    private final NativeComicArchive nativeArchive;
    private final List<ComicArchive.Entry> pages;
    final ComicManifest manifest;
    private final File scratch;
    final int pageCount;

    ComicDocument(File source,File directory,ComicArchive.Cancellation cancel)throws IOException {
        byte[] head=new byte[4];try(java.io.FileInputStream input=new java.io.FileInputStream(source)){if(input.read(head)!=4)throw new IOException("漫画包损坏");}
        boolean rar=head[0]=='R'&&head[1]=='a'&&head[2]=='r'&&head[3]=='!';
        archive=rar?null:new ComicArchive(source,cancel);
        nativeArchive=rar?new NativeComicArchive(source,cancel):null;
        try {pages=ComicArchive.pages(rar?nativeArchive.entries:archive.entries);manifest=new ComicManifest(pages);pageCount=pages.size();scratch=File.createTempFile("page-",".tmp",directory);}
        catch(IOException | RuntimeException error){if(archive!=null)archive.close();throw error;}
    }
    /** Validate every page/CRC before showing any page; cancellation never publishes a partial book. */
    void validate(ComicArchive.Cancellation cancel)throws IOException {
        if(nativeArchive!=null){nativeArchive.validatePages(pages,scratch,(file,entry)->{checkImage(file,entry);Bitmap test=decode(file,256);test.recycle();},cancel);return;}
        if(archive!=null)for(ComicArchive.Entry entry:archive.entries)if(!pages.contains(entry))archive.copy(entry,new java.io.OutputStream(){public void write(int value){}public void write(byte[] bytes,int offset,int count){}},cancel);
        for(ComicArchive.Entry entry:pages){ComicArchive.check(cancel);extract(entry,cancel);try {Bitmap test=decode(scratch,256);test.recycle();} finally {scratch.delete();}}
    }
    Bitmap page(int index,int width,ComicArchive.Cancellation cancel)throws IOException {
        if(index<0||index>=pageCount)throw new IOException("页码超出范围");
        ComicArchive.check(cancel);
        extract(pages.get(index),cancel);Bitmap bitmap;
        try {bitmap=decode(scratch,Math.max(256,Math.min(2400,width)));} finally {scratch.delete();}
        if(cancel.cancelled()){bitmap.recycle();ComicArchive.check(cancel);}
        return bitmap;
    }
    private void extract(ComicArchive.Entry entry,ComicArchive.Cancellation cancel)throws IOException {
        ComicPreviewFiles.reserve(scratch.getParentFile(),entry.size);
        try(FileOutputStream out=new FileOutputStream(scratch)){if(archive!=null)archive.copy(entry,out,cancel);else nativeArchive.copy(entry,out,cancel);}
        catch(IOException | RuntimeException error){scratch.delete();throw error;}
        checkImage(scratch,entry);
    }
    private static void checkImage(File scratch,ComicArchive.Entry entry)throws IOException {
        try(java.io.FileInputStream input=new java.io.FileInputStream(scratch)){
            byte[] head=new byte[8];int count=input.read(head);String lower=entry.name.toLowerCase(java.util.Locale.ROOT);
            boolean valid=lower.endsWith(".png")?count==8&&java.util.Arrays.equals(head,new byte[]{(byte)137,80,78,71,13,10,26,10}):count>=3&&head[0]==(byte)255&&head[1]==(byte)216&&head[2]==(byte)255;
            if(!valid){scratch.delete();throw new IOException("漫画页面扩展名与图片内容不一致");}
        }
    }
    private static Bitmap decode(File file,int width)throws IOException {
        BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),options);
        if(options.outWidth<=0||options.outHeight<=0||!"image/png".equals(options.outMimeType)&&!"image/jpeg".equals(options.outMimeType))throw new IOException("漫画页面损坏或不是 JPEG/PNG");
        if((long)options.outWidth*options.outHeight>MAX_PIXELS)throw new IOException("漫画单页超过 1 亿像素");
        int orientation=ExifInterface.ORIENTATION_NORMAL;
        if("image/jpeg".equals(options.outMimeType))orientation=new ExifInterface(file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);
        boolean swap=orientation>=5&&orientation<=8;
        int displayWidth=swap?options.outHeight:options.outWidth;
        options.inSampleSize=1;
        while((long)Math.ceil(options.outWidth/(double)options.inSampleSize)*Math.ceil(options.outHeight/(double)options.inSampleSize)*4>DECODE_BYTES||displayWidth/options.inSampleSize>width*2)options.inSampleSize*=2;
        options.inJustDecodeBounds=false;options.inPreferredConfig=Bitmap.Config.ARGB_8888;
        Bitmap bitmap;
        try {bitmap=BitmapFactory.decodeFile(file.getPath(),options);}catch(OutOfMemoryError error){throw new IOException("内存不足，无法显示漫画页面");}
        if(bitmap==null)throw new IOException("漫画页面无法解码");
        Matrix matrix=new Matrix();
        switch(orientation) {
            case 2:matrix.setScale(-1,1);break;
            case 3:matrix.setRotate(180);break;
            case 4:matrix.setScale(1,-1);break;
            case 5:matrix.setRotate(90);matrix.postScale(-1,1);break;
            case 6:matrix.setRotate(90);break;
            case 7:matrix.setRotate(-90);matrix.postScale(-1,1);break;
            case 8:matrix.setRotate(-90);break;
            default:return bitmap;
        }
        try {Bitmap rotated=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);if(rotated!=bitmap)bitmap.recycle();return rotated;}
        catch(OutOfMemoryError error){bitmap.recycle();throw new IOException("内存不足，无法校正漫画页面方向");}
    }
    @Override public void close()throws IOException {scratch.delete();if(archive!=null)archive.close();if(nativeArchive!=null)nativeArchive.close();}
}
