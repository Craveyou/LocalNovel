package com.xlib.txtreader;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.*;

/** First publication page only; disposable thumbnails never become source identity. */
final class ComicCoverCache {
    static File file(Context context,Book book){File source=new File(book.path);return new File(context.getCacheDir(),"comic-covers/"+book.id+"-"+source.length()+"-"+source.lastModified()+".jpg");}
    static Bitmap load(Context context,Book book)throws IOException {
        File destination=file(context,book);Bitmap image=BitmapFactory.decodeFile(destination.getPath());if(image!=null)return image;
        File root=destination.getParentFile();if(!root.isDirectory()&&!root.mkdirs())throw new IOException("Cannot create cover cache");
        File scratch=File.createTempFile("cover-","",root);if(!scratch.delete()||!scratch.mkdir())throw new IOException("Cannot create cover scratch");
        try(ComicDocument document=new ComicDocument(new File(book.path),scratch,()->Thread.currentThread().isInterrupted())){
            Bitmap original=document.page(0,128,()->Thread.currentThread().isInterrupted());
            try{float scale=Math.min(1,256f/Math.max(original.getWidth(),original.getHeight()));image=Bitmap.createScaledBitmap(original,Math.max(1,Math.round(original.getWidth()*scale)),Math.max(1,Math.round(original.getHeight()*scale)),true);}
            finally{if(original!=image)original.recycle();}
            File temporary=new File(scratch,"thumb.tmp");try(FileOutputStream output=new FileOutputStream(temporary)){if(!image.compress(Bitmap.CompressFormat.JPEG,85,output))throw new IOException("Cannot cache cover");}catch(IOException error){image.recycle();throw error;}
            // Failure to persist a disposable thumbnail must not prevent displaying it.
            temporary.renameTo(destination);return image;
        }finally{File[] children=scratch.listFiles();if(children!=null)for(File child:children)child.delete();scratch.delete();}
    }
}
