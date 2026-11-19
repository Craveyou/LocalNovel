package com.xlib.txtreader;
import android.content.Context;
import android.graphics.*;
import java.io.*;

/** Rebuildable thumbnail of the shared core's coverResource; never a document identity. */
final class KindleCoverCache {
    static Bitmap load(Context context,Book book)throws Exception {
        File source=new File(book.path),root=new File(context.getCacheDir(),"kindle-covers");
        if(!root.isDirectory()&&!root.mkdirs())throw new IOException("无法创建封面缓存");
        File cached=new File(root,book.id+"-"+source.length()+"-"+source.lastModified()+".png");
        Bitmap image=BitmapFactory.decodeFile(cached.getPath());if(image!=null){cached.setLastModified(System.currentTimeMillis());return image;}
        try(KindleDocument document=new KindleDocument(context,source,()->Thread.currentThread().isInterrupted())) {
            if(document.coverResource==null)throw new IOException("无内置封面");
            byte[] bytes=document.read(document.coverResource);BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;
            BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);options.inJustDecodeBounds=false;options.inSampleSize=1;
            while(Math.max(options.outWidth,options.outHeight)/options.inSampleSize>256)options.inSampleSize*=2;
            image=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);if(image==null)throw new IOException("封面解码失败");
            File temporary=File.createTempFile("cover-",".tmp",root);
            try {try(OutputStream out=new FileOutputStream(temporary)){if(!image.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("封面缓存失败");}temporary.renameTo(cached);trim(root);return image;}
            catch(Exception failure){image.recycle();throw failure;}finally{temporary.delete();}
        }
    }
    private static void trim(File directory){File[] files=directory.listFiles((root,name)->name.endsWith(".png"));if(files==null)return;java.util.Arrays.sort(files,(a,b)->Long.compare(b.lastModified(),a.lastModified()));long bytes=0;for(int i=0;i<files.length;i++){bytes+=files[i].length();if(i>=64||bytes>8L*1024*1024)files[i].delete();}}
}
