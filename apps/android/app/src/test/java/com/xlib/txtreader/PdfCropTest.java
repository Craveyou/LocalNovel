package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.content.Context;
import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.RectF;
import android.os.Looper;
import android.view.MotionEvent;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Robolectric;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import java.io.File;
import java.lang.reflect.Method;
import java.util.List;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class PdfCropTest {
    private Context context;
    private PdfPageView view;
    private ActivityController<Activity> controller;
    private int readingEvents;
    @Before public void setup(){PdfCropSettings.reset();context=RuntimeEnvironment.getApplication();}
    @After public void cleanup(){if(view!=null)view.release();if(controller!=null)controller.pause().stop().destroy();PdfCropSettings.reset();}
    private PdfPageView view(PdfDocument.Page page,int width,int height,double y){
        view=new PdfPageView(context,new PdfPageView.Listener(){public void selectionChanged(boolean selected){}public void panned(double y){readingEvents++;}});
        if(controller==null)controller=Robolectric.buildActivity(Activity.class).setup();
        controller.get().setContentView(view,new android.widget.FrameLayout.LayoutParams(width,height));idle();
        view.layout(0,0,width,height);view.page(page,y);idle();assertEquals(width,view.getWidth());assertEquals(height,view.getHeight());return view;
    }
    private static void idle(){Shadows.shadowOf(Looper.getMainLooper()).idle();}
    private Object geometry(String name,Class<?>[] types,Object...args)throws Exception{
        Method method=PdfPageView.class.getDeclaredMethod(name,types);method.setAccessible(true);return method.invoke(view,args);
    }
    private double visibleY()throws Exception{return (double)geometry("visibleY",new Class<?>[]{});}
    private Bitmap draw(){Bitmap bitmap=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);view.draw(new Canvas(bitmap));return bitmap;}
    private PdfDocument.Page bands(){
        Bitmap bitmap=Bitmap.createBitmap(1000,1000,Bitmap.Config.ARGB_8888);bitmap.eraseColor(Color.WHITE);
        for(int x=0;x<1000;x++)for(int y=0;y<1000;y++)if(x<100||x>=900)bitmap.setPixel(x,y,x<100?Color.RED:Color.BLUE);
        return new PdfDocument.Page(bitmap,"",List.of(),1000,1000);
    }
    @Test public void settingsHaveBoundedIndependentPercentagesAndProcessOnlyDefaults(){
        PdfCropSettings defaults=PdfCropSettings.current();assertFalse(defaults.enabled);assertEquals(10,defaults.leftPercent);assertEquals(10,defaults.rightPercent);
        assertEquals(0,defaults.leftFraction(),0);assertEquals(0,defaults.rightFraction(),0);
        PdfCropSettings value=new PdfCropSettings(true,-4,99);assertEquals(0,value.leftPercent);assertEquals(30,value.rightPercent);
        PdfCropSettings.setCurrent(value);assertSame(value,PdfCropSettings.current());PdfCropSettings.reset();assertEquals(defaults,PdfCropSettings.current());
    }
    @Test public void cropsRenderedLeftAndRightWithoutMutatingOrReplacingTheSource()throws Exception{
        PdfDocument.Page source=bands();view(source,600,400,0);
        Bitmap original=draw();assertEquals(Color.RED,original.getPixel(105,100));assertEquals(Color.BLUE,original.getPixel(495,100));original.recycle();
        view.crop(new PdfCropSettings(true,10,10));Bitmap cropped=draw();
        assertEquals(Color.WHITE,cropped.getPixel(5,100));assertEquals(Color.WHITE,cropped.getPixel(595,100));cropped.recycle();
        view.crop(new PdfCropSettings(true,30,0));cropped=draw();assertEquals(Color.WHITE,cropped.getPixel(5,100));assertEquals(Color.BLUE,cropped.getPixel(595,100));cropped.recycle();
        view.crop(new PdfCropSettings(true,0,30));cropped=draw();assertEquals(Color.RED,cropped.getPixel(5,100));assertEquals(Color.WHITE,cropped.getPixel(595,100));cropped.recycle();
        view.crop(new PdfCropSettings(true,30,30));cropped=draw();assertEquals(Color.WHITE,cropped.getPixel(5,100));assertEquals(Color.WHITE,cropped.getPixel(595,100));cropped.recycle();
        assertFalse(source.bitmap.isRecycled());assertEquals(Color.RED,source.bitmap.getPixel(0,100));assertEquals(Color.BLUE,source.bitmap.getPixel(999,100));
        view.crop(PdfCropSettings.defaults());cropped=draw();assertEquals(Color.RED,cropped.getPixel(105,100));cropped.recycle();assertEquals(0,readingEvents);
    }
    @Test public void cropAndResizeKeepOriginalVerticalCoordinatesAndCroppedPagePansAtBaseZoom()throws Exception{
        view(bands(),600,400,.3);assertEquals(.3,visibleY(),.0001);
        view.crop(new PdfCropSettings(true,10,20));assertEquals(.3,visibleY(),.0001);
        view.layout(0,0,700,350);assertEquals(.3,visibleY(),.0001);assertEquals(0,readingEvents);
        long down=android.os.SystemClock.uptimeMillis();
        for(int action:new int[]{MotionEvent.ACTION_DOWN,MotionEvent.ACTION_MOVE,MotionEvent.ACTION_UP}){
            MotionEvent event=MotionEvent.obtain(down,down+(action==MotionEvent.ACTION_DOWN?0:50),action,300,action==MotionEvent.ACTION_DOWN?250:150,0);view.onTouchEvent(event);event.recycle();
        }
        assertTrue(visibleY()>.3);assertEquals(1,readingEvents);
    }
    @Test public void hiddenMarginTextCannotBeSelectedAndOriginalOffsetsStayUnchanged()throws Exception{
        Bitmap bitmap=Bitmap.createBitmap(1000,1000,Bitmap.Config.ARGB_8888);
        PdfDocument.Page page=new PdfDocument.Page(bitmap,"ab",List.of(new RectF(0,20,50,60),new RectF(400,500,450,550)),1000,1000);
        view(page,600,400,0);int offset=view.firstTextOffset(.4);view.crop(new PdfCropSettings(true,30,30));
        assertEquals(offset,view.firstTextOffset(.4));assertEquals(-1,(int)geometry("character",new Class<?>[]{float.class,float.class},-10f,30f));
        RectF hidden=(RectF)geometry("box",new Class<?>[]{int.class},0);
        assertEquals(-1,(int)geometry("character",new Class<?>[]{float.class,float.class},hidden.centerX(),hidden.centerY()));
        view.highlight(1,2);idle();RectF shown=(RectF)geometry("box",new Class<?>[]{int.class},1);
        assertEquals(1,(int)geometry("character",new Class<?>[]{float.class,float.class},shown.centerX(),shown.centerY()));assertEquals(0,readingEvents);
    }
    @Test public void rotatedPagesKeepSearchHighlightAndTextBoxesOnTheDisplayedGlyphsAfterCropping()throws Exception{
        for(int rotation:new int[]{0,90,180,270}){
            File base=PdfDocumentTest.fixture(context,"crop-base.pdf",null,true,true),file=new File(context.getCacheDir(),"crop-"+rotation+".pdf");
            try(PDDocument document=PDDocument.load(base)){document.getPage(0).setRotation(rotation);document.save(file);}
            try(PdfDocument pdf=new PdfDocument(context,file,null)){
                PdfDocument.Page page=pdf.render(0,800);view(page,600,400,0);view.crop(new PdfCropSettings(true,2,3));
                int offset=view.firstTextOffset(0);view.highlight(0,1);idle();assertEquals(offset,view.firstTextOffset(0));
                RectF glyph=(RectF)geometry("box",new Class<?>[]{int.class},0);Bitmap display=draw();boolean ink=false;
                for(int y=Math.max(0,(int)glyph.top-3);y<Math.min(display.getHeight(),(int)glyph.bottom+3);y++)
                    for(int x=Math.max(0,(int)glyph.left-3);x<Math.min(display.getWidth(),(int)glyph.right+3);x++)if(Color.red(display.getPixel(x,y))<200)ink=true;
                assertTrue("Cropped text missed glyph at rotation "+rotation,ink);display.recycle();view.release();view=null;
            }
        }
        assertEquals(0,readingEvents);
    }
}
