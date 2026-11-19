package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Debug;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.SeekBar;
import android.widget.TextView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;
import java.util.zip.*;
import org.json.*;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Disposable emulator flows only. Fixtures are authored here, without real books or network access. */
@RunWith(AndroidJUnit4.class)
public class ComicPreviewDeviceTest {
    private final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    private final Context context=instrument.getTargetContext();
    private ComicPreviewActivity activity;
    private File source;
    @Before public void setup()throws Exception {
        assertTrue(android.os.Build.FINGERPRINT.contains("generic")||android.os.Build.MODEL.contains("sdk"));
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){ReadingPreferences p=new ReadingPreferences(db);p.setAppTheme(ReaderSettingsOptions.THEME_LIGHT);p.setComicRightToLeft(false);}
    }
    @After public void cleanup()throws Exception {finish();if(source!=null)source.delete();try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){new ReadingPreferences(db).setComicRightToLeft(false);new ReadingPreferences(db).setAppTheme(ReaderSettingsOptions.THEME_LIGHT);}}
    private static Object field(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private void waitFor(BooleanSupplier condition)throws Exception {long deadline=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<deadline){instrument.waitForIdleSync();if(condition.getAsBoolean())return;Thread.sleep(30);}fail("Comic preview timed out");}
    private boolean opened(){try{return (int)field(activity,"page")>=0;}catch(Exception error){throw new AssertionError(error);}}
    private int page()throws Exception{return (int)field(activity,"page");}
    private ComicPageView view()throws Exception{return (ComicPageView)field(activity,"pageView");}
    private void launch(File file)throws Exception {source=file;activity=(ComicPreviewActivity)instrument.startActivitySync(new Intent(context,ComicPreviewActivity.class).setData(Uri.fromFile(file)).putExtra("sourceName","sample.CBZ").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}
    private void ready()throws Exception{waitFor(this::opened);waitFor(activity::hasWindowFocus);Thread.sleep(350);}
    private void finish()throws Exception {if(activity==null)return;ExecutorService worker=(ExecutorService)field(activity,"worker");instrument.runOnMainSync(()->activity.finish());assertTrue(worker.awaitTermination(10,TimeUnit.SECONDS));instrument.waitForIdleSync();activity=null;}
    private AccessibilityNodeInfo find(AccessibilityNodeInfo node,String label){if(node==null)return null;if(label.contentEquals(node.getText()==null?"":node.getText())||label.contentEquals(node.getContentDescription()==null?"":node.getContentDescription()))return node;for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo found=find(node.getChild(i),label);if(found!=null)return found;}return null;}
    private AccessibilityNodeInfo control(String label)throws Exception {final AccessibilityNodeInfo[] result={null};waitFor(()->{result[0]=find(instrument.getUiAutomation().getRootInActiveWindow(),label);return result[0]!=null;});return result[0];}
    private void click(String label)throws Exception {AccessibilityNodeInfo node=control(label);while(!node.isClickable()&&node.getParent()!=null)node=node.getParent();assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK));instrument.waitForIdleSync();Thread.sleep(250);}
    private void pointer(long down,int action,float x,float y){MotionEvent event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);instrument.sendPointerSync(event);event.recycle();}
    private void swipe(float x0,float y0,float x1,float y1)throws Exception{ComicPageView view=view();int[] xy=new int[2];instrument.runOnMainSync(()->view.getLocationOnScreen(xy));long down=SystemClock.uptimeMillis();pointer(down,MotionEvent.ACTION_DOWN,xy[0]+view.getWidth()*x0,xy[1]+view.getHeight()*y0);for(int i=1;i<=12;i++){Thread.sleep(16);pointer(down,MotionEvent.ACTION_MOVE,xy[0]+view.getWidth()*(x0+(x1-x0)*i/12),xy[1]+view.getHeight()*(y0+(y1-y0)*i/12));}pointer(down,MotionEvent.ACTION_UP,xy[0]+view.getWidth()*x1,xy[1]+view.getHeight()*y1);instrument.waitForIdleSync();}
    private void menus()throws Exception {if((boolean)field(activity,"menus"))return;ComicPageView view=view();int[] xy=new int[2];instrument.runOnMainSync(()->view.getLocationOnScreen(xy));long down=SystemClock.uptimeMillis();pointer(down,MotionEvent.ACTION_DOWN,xy[0]+view.getWidth()*.45f,xy[1]+view.getHeight()/2f);pointer(down,MotionEvent.ACTION_UP,xy[0]+view.getWidth()*.45f,xy[1]+view.getHeight()/2f);Thread.sleep(android.view.ViewConfiguration.getDoubleTapTimeout()+80);instrument.waitForIdleSync();assertTrue((boolean)field(activity,"menus"));}
    private void hideMenus()throws Exception{instrument.runOnMainSync(()->activity.onBackPressed());instrument.waitForIdleSync();}
    private void screenshot(String name)throws Exception {Bitmap image=instrument.getUiAutomation().takeScreenshot();try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),name))){assertTrue(image.compress(Bitmap.CompressFormat.PNG,100,out));}image.recycle();}
    private Bitmap drawn()throws Exception{ComicPageView view=view();Bitmap[] result={null};instrument.runOnMainSync(()->{result[0]=Bitmap.createBitmap(view.getWidth(),view.getHeight(),Bitmap.Config.ARGB_8888);view.draw(new Canvas(result[0]));});return result[0];}
    private File fixture(int pages,boolean corrupt)throws Exception {
        File file=File.createTempFile("comic-device-",".cbz",context.getCacheDir());byte[] red=png(600,3200,255,0,0),blue=png(600,1000,0,0,255),green=png(600,1000,0,255,0);
        try(ZipOutputStream out=new ZipOutputStream(new FileOutputStream(file))){
            if(pages==3){entry(out,"10.png",green);entry(out,"2.png",blue);entry(out,"1.png",red);entry(out,".hidden/unsupported.webp",new byte[]{1});}
            else for(int i=0;i<pages;i++)entry(out,i+".png",corrupt&&i==pages-1?new byte[]{1,2,3}:blue);
        }
        return file;
    }
    private static void entry(ZipOutputStream zip,String name,byte[] bytes)throws Exception {zip.putNextEntry(new ZipEntry(name));zip.write(bytes);zip.closeEntry();}
    /** Streaming RGB PNG generator; never allocates the full giant source image. */
    private static byte[] png(int width,int height,int red,int green,int blue)throws Exception {
        ByteArrayOutputStream compressed=new ByteArrayOutputStream();byte[] row=new byte[1+width*3];for(int i=1;i<row.length;i+=3){row[i]=(byte)red;row[i+1]=(byte)green;row[i+2]=(byte)blue;}
        try(DeflaterOutputStream out=new DeflaterOutputStream(compressed)){for(int i=0;i<height;i++)out.write(row);}
        ByteArrayOutputStream image=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(image);out.write(new byte[]{(byte)137,80,78,71,13,10,26,10});ByteArrayOutputStream header=new ByteArrayOutputStream();DataOutputStream fields=new DataOutputStream(header);fields.writeInt(width);fields.writeInt(height);fields.write(new byte[]{8,2,0,0,0});chunk(out,"IHDR",header.toByteArray());chunk(out,"IDAT",compressed.toByteArray());chunk(out,"IEND",new byte[0]);return image.toByteArray();
    }
    private static void chunk(DataOutputStream out,String type,byte[] data)throws Exception{byte[] tag=type.getBytes(StandardCharsets.US_ASCII);out.writeInt(data.length);out.write(tag);out.write(data);CRC32 crc=new CRC32();crc.update(tag);crc.update(data);out.writeInt((int)crc.getValue());}
    private long[] libraryCounts()throws Exception {try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){long[] values=new long[3];String[] tables={"books","document_positions","document_bookmarks"};for(int i=0;i<3;i++)try(android.database.Cursor cursor=db.getReadableDatabase().rawQuery("select count(*) from "+tables[i],null)){assertTrue(cursor.moveToFirst());values[i]=cursor.getLong(0);}return values;}}

    @Test public void realGesturesSeekJumpThemeAndRecreationKeepPreviewIsolated()throws Exception {
        long[] before=libraryCounts();File file=fixture(3,false);byte[] original=Files.readAllBytes(file.toPath());launch(file);ready();assertEquals(0,page());assertEquals(3,(int)field(activity,"count"));
        Bitmap image=drawn();assertEquals(Color.RED,image.getPixel(image.getWidth()/2,image.getHeight()/2));image.recycle();
        swipe(.45f,.8f,.45f,.25f);assertTrue(view().anchor()>0);double anchor=view().anchor();menus();screenshot("comic-light-menu.png");click("放大漫画");assertEquals(anchor,view().anchor(),.00001);click("切换阅读主题");
        image=drawn();assertEquals(Color.RED,image.getPixel(image.getWidth()/2,image.getHeight()/2));image.recycle();screenshot("comic-dark-menu.png");assertFalse(control("搜索").isEnabled());assertFalse(control("书签").isEnabled());
        hideMenus();menus();click("切换适宽或整页");click("切换适宽或整页");
        click("调整阅读进度");SeekBar seek=(SeekBar)field(activity,"seek");int[] xy=new int[2];instrument.runOnMainSync(()->seek.getLocationOnScreen(xy));long down=SystemClock.uptimeMillis();float x=xy[0]+seek.getWidth()*.55f,y=xy[1]+seek.getHeight()/2f;pointer(down,MotionEvent.ACTION_DOWN,x,y);pointer(down,MotionEvent.ACTION_MOVE,xy[0]+seek.getWidth()*.95f,y);
        instrument.runOnMainSync(()->assertFalse(((TextView)uncheckedField(activity,"percentage")).getText().toString().startsWith("0.0")));pointer(down,MotionEvent.ACTION_UP,xy[0]+seek.getWidth()*.95f,y);waitFor(()->{try{return page()==2;}catch(Exception e){throw new AssertionError(e);}});assertTrue(((TextView)field(activity,"status")).getText().toString().contains("100.0%"));
        click("跳页");AccessibilityNodeInfo input=findClass(instrument.getUiAutomation().getRootInActiveWindow(),"android.widget.EditText");assertNotNull(input);Bundle text=new Bundle();text.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"1");assertTrue(input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,text));click("前往");waitFor(()->{try{return page()==0;}catch(Exception e){throw new AssertionError(e);}});
        click("漫画阅读设置");click("阅读方向：从左向右");hideMenus();waitFor(activity::hasWindowFocus);assertTrue((boolean)field(activity,"rtl"));assertFalse((boolean)field(activity,"menus"));assertEquals(1f,(float)field(view(),"zoom"),.001f);screenshot("modern-comic-before-rtl-swipe.png");swipe(.15f,.5f,.85f,.5f);screenshot("modern-comic-after-rtl-swipe.png");try{waitFor(()->{try{return page()==1;}catch(Exception e){throw new AssertionError(e);}});}catch(AssertionError error){throw new AssertionError("After RTL swipe page="+page()+" zoom="+field(view(),"zoom")+" menus="+field(activity,"menus")+" direction="+field(activity,"rtl"),error);}
        menus();screenshot("comic-preview-menu.png");hideMenus();
        Instrumentation.ActivityMonitor monitor=instrument.addMonitor(ComicPreviewActivity.class.getName(),null,false);instrument.runOnMainSync(()->activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));activity=(ComicPreviewActivity)instrument.waitForMonitorWithTimeout(monitor,10000);instrument.removeMonitor(monitor);assertNotNull(activity);ready();assertEquals(1,page());assertTrue((boolean)field(activity,"rtl"));
        assertArrayEquals(before,libraryCounts());assertArrayEquals(original,Files.readAllBytes(file.toPath()));File directory=(File)field(activity,"directory");finish();assertFalse(directory.exists());assertArrayEquals(before,libraryCounts());
    }
    private static Object uncheckedField(Object target,String name){try{return field(target,name);}catch(Exception error){throw new AssertionError(error);}}
    private AccessibilityNodeInfo findClass(AccessibilityNodeInfo node,String name){if(node==null)return null;if(name.contentEquals(node.getClassName()))return node;for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo found=findClass(node.getChild(i),name);if(found!=null)return found;}return null;}

    @Test public void corruptLatePageAndCancellationLeaveNoLibraryRecordsOrPreviewFiles()throws Exception {
        long[] before=libraryCounts();launch(fixture(4,true));waitFor(()->{try{return "漫画无法打开".contentEquals(((TextView)field(activity,"status")).getText());}catch(Exception e){throw new AssertionError(e);}});assertEquals(-1,page());File directory=(File)field(activity,"directory");finish();assertFalse(directory.exists());source.delete();
        launch(fixture(5000,false));directory=(File)field(activity,"directory");finish();if(directory!=null)assertFalse(directory.exists());assertArrayEquals(before,libraryCounts());
    }

    @Test public void largeImageDecodeAndRandomJumpsHaveRepeatableSimulatorMeasurements()throws Exception {
        File file=File.createTempFile("comic-large-",".cbz",context.getCacheDir());source=file;
        try(ZipOutputStream zip=new ZipOutputStream(new FileOutputStream(file))){byte[] giant=png(4000,6000,120,70,30);for(int i=0;i<12;i++)entry(zip,i+".png",giant);}
        JSONArray measurements=new JSONArray();
        for(int round=0;round<3;round++) {
            long started=SystemClock.elapsedRealtimeNanos();launch(file);waitFor(this::opened);long first=SystemClock.elapsedRealtimeNanos()-started;
            ComicDocument document=(ComicDocument)field(activity,"document");ExecutorService worker=(ExecutorService)field(activity,"worker");final long[] latency={0};
            worker.submit(()->{try{long start=SystemClock.elapsedRealtimeNanos();Bitmap bitmap=document.page(11,1080,ComicArchive.NEVER);latency[0]=SystemClock.elapsedRealtimeNanos()-start;assertTrue(bitmap.getAllocationByteCount()<=ComicDocument.DECODE_BYTES);bitmap.recycle();}catch(Exception error){throw new AssertionError(error);}}).get(20,TimeUnit.SECONDS);
            Debug.MemoryInfo memory=new Debug.MemoryInfo();Debug.getMemoryInfo(memory);measurements.put(new JSONObject().put("firstScreenMs",first/1e6).put("uncachedDecodePage11Ms",latency[0]/1e6).put("sampledProcessPssKiB",memory.getTotalPss()));finish();
        }
        JSONObject report=new JSONObject().put("device",android.os.Build.MODEL).put("sdk",android.os.Build.VERSION.SDK_INT).put("mode","debug emulator POC; PSS is a point sample, not peak memory").put("sourceBytes",file.length()).put("pages",12).put("sourcePixelsPerPage",24000000).put("measurements",measurements);
        try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),"comic-preview-measurements.json"))){out.write(report.toString(2).getBytes(StandardCharsets.UTF_8));}
    }
}
