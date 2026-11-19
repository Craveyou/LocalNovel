package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.os.Looper;
import android.view.MotionEvent;
import java.io.*;
import java.util.zip.*;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;

@RunWith(RobolectricTestRunner.class) @Config(sdk=35) @GraphicsMode(GraphicsMode.Mode.NATIVE)
public class ComicRenderingTest {
    private final Context context=RuntimeEnvironment.getApplication();
    private ActivityController<Activity> controller;
    private ComicPageView view;
    private int turns,taps;
    private Bitmap image(int width,int height){Bitmap image=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888);image.eraseColor(Color.RED);return image;}
    private ComicPageView attach(Bitmap image,double y){controller=Robolectric.buildActivity(Activity.class).setup();view=new ComicPageView(context,new ComicPageView.Listener(){public void tap(float f){taps++;}public void turn(int d){turns+=d;}public boolean dismissMenus(){return false;}});controller.get().setContentView(view,new android.widget.FrameLayout.LayoutParams(600,400));Shadows.shadowOf(Looper.getMainLooper()).idle();view.layout(0,0,600,400);view.page(image,y);return view;}
    private void touch(int action,long down,long time,float x,float y){MotionEvent event=MotionEvent.obtain(down,time,action,x,y,0);view.onTouchEvent(event);event.recycle();}
    @After public void close(){if(view!=null)view.release();if(controller!=null)controller.pause().stop().destroy();}
    @Test public void longImagePansAtFitWidthAndFittingZoomThemeResizeDoNotChangeSessionAnchor(){
        Bitmap source=image(600,2400);attach(source,.3);view.background(UiKit.DARK_BACKGROUND);
        Bitmap rendered=Bitmap.createBitmap(600,400,Bitmap.Config.ARGB_8888);view.draw(new Canvas(rendered));assertEquals(Color.RED,rendered.getPixel(300,200));rendered.recycle();
        view.zoomBy(2);view.fitWidth(false);view.layout(0,0,400,600);view.fitWidth(true);assertEquals(.3,view.anchor(),.00001);
        long down=android.os.SystemClock.uptimeMillis();touch(MotionEvent.ACTION_DOWN,down,down,200,300);touch(MotionEvent.ACTION_MOVE,down,down+70,200,100);touch(MotionEvent.ACTION_UP,down,down+90,200,100);
        assertTrue(view.anchor()>.3);assertEquals(0,turns);assertEquals(Color.RED,source.getPixel(1,1));source.recycle();
    }
    @Test public void horizontalFlingTurnsAtBaseZoomButPansWhenZoomed(){
        Bitmap source=image(1000,1000);attach(source,0);long down=android.os.SystemClock.uptimeMillis();touch(MotionEvent.ACTION_DOWN,down,down,580,200);touch(MotionEvent.ACTION_MOVE,down,down+20,250,200);touch(MotionEvent.ACTION_UP,down,down+40,20,200);assertEquals(1,turns);
        view.zoomBy(2);down+=1000;touch(MotionEvent.ACTION_DOWN,down,down,580,200);touch(MotionEvent.ACTION_MOVE,down,down+20,250,200);touch(MotionEvent.ACTION_UP,down,down+40,20,200);assertEquals(1,turns);source.recycle();
    }
    @Test public void slowHorizontalDragTurnsOnceWithoutRequiringFlingVelocity(){
        Bitmap source=image(600,800);attach(source,0);long down=android.os.SystemClock.uptimeMillis();
        touch(MotionEvent.ACTION_DOWN,down,down,550,200);touch(MotionEvent.ACTION_MOVE,down,down+1500,300,200);touch(MotionEvent.ACTION_UP,down,down+3000,30,200);assertEquals(1,turns);
        down+=4000;touch(MotionEvent.ACTION_DOWN,down,down,30,200);touch(MotionEvent.ACTION_MOVE,down,down+1500,300,200);touch(MotionEvent.ACTION_UP,down,down+3000,550,200);assertEquals(0,turns);source.recycle();
    }
    private File archive(byte[] page,String name)throws Exception {File file=File.createTempFile("comic-",".cbz",context.getCacheDir());try(ZipOutputStream zip=new ZipOutputStream(new FileOutputStream(file))){zip.putNextEntry(new ZipEntry(name));zip.write(page);zip.closeEntry();}return file;}
    @Test public void sampledDecodingHasPixelBudgetAndValidationNeverMutatesOriginal()throws Exception {
        Bitmap original=image(4000,6000);ByteArrayOutputStream out=new ByteArrayOutputStream();assertTrue(original.compress(Bitmap.CompressFormat.PNG,100,out));original.recycle();byte[] bytes=out.toByteArray();File source=archive(bytes,"1.png");byte[] before=java.nio.file.Files.readAllBytes(source.toPath());
        File dir=new File(context.getCacheDir(),"comic-render-test");dir.mkdirs();
        try(ComicDocument document=new ComicDocument(source,dir,ComicArchive.NEVER)){
            document.validate(ComicArchive.NEVER);Bitmap rendered=document.page(0,600,ComicArchive.NEVER);assertTrue(rendered.getAllocationByteCount()<=ComicDocument.DECODE_BYTES);assertTrue(rendered.getWidth()<4000);assertEquals(Color.RED,rendered.getPixel(1,1));rendered.recycle();
            assertThrows(IOException.class,()->document.page(0,600,()->true));assertThrows(IOException.class,()->document.page(1,600,ComicArchive.NEVER));
        }
        assertArrayEquals(before,java.nio.file.Files.readAllBytes(source.toPath()));assertEquals(0,dir.list().length);
    }
    @Test public void everyPageMustValidateAndRenamedImageBytesCannotSlipThrough()throws Exception {
        Bitmap bitmap=image(80,80);ByteArrayOutputStream out=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.PNG,100,out);bitmap.recycle();
        for(File file:new File[]{archive(out.toByteArray(),"1.jpg"),archive(new byte[]{1,2,3},"1.png")}){
            File dir=new File(context.getCacheDir(),"comic-bad-test");dir.mkdirs();
            try(ComicDocument document=new ComicDocument(file,dir,ComicArchive.NEVER)){assertThrows(IOException.class,()->document.validate(ComicArchive.NEVER));}
            assertEquals(0,dir.list().length);
        }
    }
    @Test public void jpegExifOrientationDefinesTheDisplayedNaturalImage()throws Exception {
        Bitmap original=image(800,1200);File jpeg=File.createTempFile("oriented-",".jpg",context.getCacheDir());try(FileOutputStream out=new FileOutputStream(jpeg)){assertTrue(original.compress(Bitmap.CompressFormat.JPEG,95,out));}original.recycle();
        android.media.ExifInterface exif=new android.media.ExifInterface(jpeg.getPath());exif.setAttribute(android.media.ExifInterface.TAG_ORIENTATION,"6");exif.saveAttributes();
        File source=archive(java.nio.file.Files.readAllBytes(jpeg.toPath()),"1.jpeg");File dir=new File(context.getCacheDir(),"comic-orientation-test");dir.mkdirs();
        try(ComicDocument document=new ComicDocument(source,dir,ComicArchive.NEVER)){document.validate(ComicArchive.NEVER);Bitmap decoded=document.page(0,1800,ComicArchive.NEVER);assertEquals(1200,decoded.getWidth());assertEquals(800,decoded.getHeight());decoded.recycle();}
        jpeg.delete();source.delete();
    }
}
