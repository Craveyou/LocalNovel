package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Instrumentation;
import android.content.*;
import android.graphics.Bitmap;
import android.os.*;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;
import java.util.zip.*;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class ComicLibraryDeviceTest {
    final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    final Context context=instrument.getTargetContext(),test=instrument.getContext();
    ComicPreviewActivity activity;File source;Book book;
    final List<File> files=new ArrayList<>();
    @Before public void setup(){assertTrue(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic"));}
    File fixture(String name)throws Exception {File f=File.createTempFile("comic-native-",".bin",context.getCacheDir());files.add(f);try(InputStream input=test.getAssets().open("documents/"+name);OutputStream output=new FileOutputStream(f)){byte[] bytes=new byte[65536];int n;while((n=input.read(bytes))!=-1)output.write(bytes,0,n);}return f;}
    JSONObject json(String name)throws Exception {try(InputStream input=test.getAssets().open("documents/"+name)){ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] bytes=new byte[8192];int n;while((n=input.read(bytes))!=-1)out.write(bytes,0,n);return new JSONObject(out.toString("UTF-8"));}}
    static String hash(byte[] bytes)throws Exception {byte[] digest=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder s=new StringBuilder();for(byte b:digest)s.append(String.format(Locale.ROOT,"%02x",b&255));return s.toString();}
    @After public void close()throws Exception {finish();if(book!=null)try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){db.deleteBook(book);}for(File f:files)f.delete();}
    Object field(Object object,String name){try{Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);}catch(Exception e){throw new AssertionError(e);}}
    void waitFor(BooleanSupplier check)throws Exception {long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();if(check.getAsBoolean())return;Thread.sleep(25);}fail("Comic flow timed out");}
    int page(){return (int)field(activity,"page");}
    void launch()throws Exception {activity=(ComicPreviewActivity)instrument.startActivitySync(new Intent(context,ComicPreviewActivity.class).putExtra("bookId",book.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));waitFor(()->page()>=0&&!(boolean)field(activity,"opening")&&field(activity,"sync")!=null&&((DocumentSyncSession)field(activity,"sync")).canRead());waitFor(activity::hasWindowFocus);}
    void finish()throws Exception {if(activity==null)return;ExecutorService executor=(ExecutorService)field(activity,"worker");instrument.runOnMainSync(()->activity.finish());assertTrue(executor.awaitTermination(15,TimeUnit.SECONDS));instrument.waitForIdleSync();activity=null;}
    void invoke(String name,Class<?>[] types,Object... args)throws Exception {Method method=ComicPreviewActivity.class.getDeclaredMethod(name,types);method.setAccessible(true);instrument.runOnMainSync(()->{try{method.invoke(activity,args);}catch(Exception e){throw new AssertionError(e);}});instrument.waitForIdleSync();}
    void screenshot(String name)throws Exception {Thread.sleep(350);Bitmap image=instrument.getUiAutomation().takeScreenshot();try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),name))){assertTrue(image.compress(Bitmap.CompressFormat.PNG,100,out));}image.recycle();}
    void send(long down,int action,float x,float y){MotionEvent e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);instrument.sendPointerSync(e);e.recycle();}
    AccessibilityNodeInfo find(AccessibilityNodeInfo n,String label){if(n==null)return null;if(label.contentEquals(n.getText()==null?"":n.getText())||label.contentEquals(n.getContentDescription()==null?"":n.getContentDescription()))return n;for(int i=0;i<n.getChildCount();i++){AccessibilityNodeInfo value=find(n.getChild(i),label);if(value!=null)return value;}return null;}
    void click(String label)throws Exception {waitFor(()->find(instrument.getUiAutomation().getRootInActiveWindow(),label)!=null);AccessibilityNodeInfo n=find(instrument.getUiAutomation().getRootInActiveWindow(),label);if(n==null){Bitmap screenshot=instrument.getUiAutomation().takeScreenshot();try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),"comic-failure.png"))){screenshot.compress(Bitmap.CompressFormat.PNG,100,out);}screenshot.recycle();}assertNotNull(label+" : "+tree(instrument.getUiAutomation().getRootInActiveWindow()),n);while(!n.isClickable()&&n.getParent()!=null)n=n.getParent();assertTrue(n.performAction(AccessibilityNodeInfo.ACTION_CLICK));instrument.waitForIdleSync();Thread.sleep(200);}
    String tree(AccessibilityNodeInfo n){if(n==null)return "null";String value="["+n.getText()+"/"+n.getContentDescription()+"]";for(int i=0;i<n.getChildCount();i++)value+=tree(n.getChild(i));return value;}
    Book saved()throws Exception {try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){for(Book b:db.loadBooks())if(b.id==book.id)return b;}throw new AssertionError("Missing book");}
    void importOriginal(String name)throws Exception {
        File input=fixture(name);DocumentFormats.validate(context,input,DocumentFormats.detect(input,name));List<Book> published=new ArrayList<>();int[] failed={0};
        File directory=new File(context.getFilesDir(),"books");
        BookImportController<File> controller=new BookImportController<>(directory,new BookImportController.Source<File>(){
            public String name(File f){return name;}public InputStream open(File f)throws Exception{return new FileInputStream(f);}
            public void validate(File f,String format,ComicArchive.Cancellation cancel)throws Exception{DocumentFormats.validate(context,f,format,cancel);}
        },Runnable::run,Runnable::run,new BookImportController.Listener(){public void changed(){}public void publish(Book b){published.add(b);}public void finished(int added,int duplicates,int errors){failed[0]=errors;}});
        controller.importBooks(Collections.singletonList(input),Collections.emptyList());assertEquals(0,failed[0]);assertEquals(1,published.size());book=published.get(0);source=new File(book.path);assertArrayEquals(Files.readAllBytes(input.toPath()),Files.readAllBytes(source.toPath()));
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){List<Book> library=db.loadBooks();library.add(book);assertTrue(db.saveBooks(library,null,0,0));}controller.close();
    }
    @Test public void sharedCbzRar4Rar5AndSolidArchivesHaveIdenticalPagesAndNativeCancellation()throws Exception {
        JSONArray measurements=new JSONArray();
        for(String name:new String[]{"comic-basic.cbz","comic-basic-rar4.cbr","comic-basic-rar5.cbr","comic-basic-rar4-solid.cbr"}){
            File file=fixture(name);JSONObject expected=json(name.replace(".cbz",".json").replace(".cbr",".json"));long start=SystemClock.elapsedRealtimeNanos();JSONObject timing=new JSONObject().put("file",name);
            try(NativeComicArchive archive=new NativeComicArchive(file,ComicArchive.NEVER)){
                timing.put("initialScanMs",(SystemClock.elapsedRealtimeNanos()-start)/1e6);long readsAt=SystemClock.elapsedRealtimeNanos();
                List<ComicArchive.Entry> pages=ComicArchive.pages(archive.entries);ComicManifest manifest=new ComicManifest(pages);assertEquals(expected.getString("manifestHash"),manifest.hash);assertEquals(24,pages.size());
                for(int i:new int[]{23,10,0,12,23}){ByteArrayOutputStream bytes=new ByteArrayOutputStream();archive.copy(pages.get(i),bytes,ComicArchive.NEVER);assertEquals(json("comic-basic.json").getJSONArray("pages").getJSONObject(i).getString("sha256"),hash(bytes.toByteArray()));}
                timing.put("fiveRandomReadsMs",(SystemClock.elapsedRealtimeNanos()-readsAt)/1e6);long cancellationAt=SystemClock.elapsedRealtimeNanos();int[] checks={0};assertThrows(IOException.class,()->archive.copy(pages.get(23),new ByteArrayOutputStream(),()->++checks[0]>1));ByteArrayOutputStream retry=new ByteArrayOutputStream();archive.copy(pages.get(0),retry,ComicArchive.NEVER);assertEquals(json("comic-basic.json").getJSONArray("pages").getJSONObject(0).getString("sha256"),hash(retry.toByteArray()));timing.put("cancelAndRetryMs",(SystemClock.elapsedRealtimeNanos()-cancellationAt)/1e6);
            }
            long decodeAt=SystemClock.elapsedRealtimeNanos();File scratch=new File(context.getCacheDir(),"native-validate");scratch.mkdirs();try(ComicDocument document=new ComicDocument(file,scratch,ComicArchive.NEVER)){document.validate(ComicArchive.NEVER);Bitmap image=document.page(10,1080,ComicArchive.NEVER);assertTrue(image.getAllocationByteCount()<=ComicDocument.DECODE_BYTES);image.recycle();}scratch.delete();
            timing.put("fullImageValidationAndLongPageDecodeMs",(SystemClock.elapsedRealtimeNanos()-decodeAt)/1e6);measurements.put(timing.put("scanDecodeAndFiveRandomReadsMs",(SystemClock.elapsedRealtimeNanos()-start)/1e6));
        }
        try(InputStream license=context.getAssets().open("UnRAR-LICENSE.txt")){ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] b=new byte[4096];int n;while((n=license.read(b))!=-1)bytes.write(b,0,n);assertTrue(bytes.toString("UTF-8").contains("RAR compression algorithm"));}
        JSONObject report=new JSONObject().put("mode","debug emulator, synthetic 24-page fixtures; not physical-device peak memory").put("sdk",android.os.Build.VERSION.SDK_INT).put("measurements",measurements);try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),"comic-native-measurements.json"))){out.write(report.toString(2).getBytes(StandardCharsets.UTF_8));}
    }
    @Test public void formalSolidComicImportBookmarkTemporaryNavigationAndCacheReopenPreserveIdentity()throws Exception {
        importOriginal("comic-basic-rar4-solid.cbr");byte[] original=Files.readAllBytes(source.toPath());launch();assertEquals(0,page());assertEquals(0,saved().updatedAt);assertEquals(1d/24,saved().locator.progress(),0);
        invoke("navigate",new Class[]{int.class,double.class},10,.25);waitFor(()->page()==10);Book reading=saved();assertTrue(reading.updatedAt>0);assertEquals(.25,reading.locator.y,0);
        ComicPageView content=(ComicPageView)field(activity,"pageView");int[] origin=new int[2];instrument.runOnMainSync(()->content.getLocationOnScreen(origin));long down=SystemClock.uptimeMillis();float x=origin[0]+content.getWidth()*.45f,y=origin[1]+content.getHeight()*.8f;send(down,MotionEvent.ACTION_DOWN,x,y);for(int i=1;i<=12;i++){Thread.sleep(16);send(down,MotionEvent.ACTION_MOVE,x,y-content.getHeight()*.5f*i/12);}send(down,MotionEvent.ACTION_UP,x,y-content.getHeight()*.5f);instrument.waitForIdleSync();assertTrue(saved().locator.y>.25);assertTrue(saved().updatedAt>reading.updatedAt);
        Bitmap cover=ComicCoverCache.load(context,book);assertTrue(cover.getWidth()<=256&&cover.getHeight()<=256);cover.recycle();File coverFile=ComicCoverCache.file(context,book);assertTrue(coverFile.delete());cover=ComicCoverCache.load(context,book);cover.recycle();assertArrayEquals(original,Files.readAllBytes(source.toPath()));
        invoke("bookmarks",new Class[]{});screenshot("comic-formal-bookmarks.png");click("添加当前位置");click("知道了");
        invoke("bookmarks",new Class[]{});click("添加当前位置");click("知道了");try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertEquals(1,db.documentBookmarks(book.id).size());}
        invoke("navigate",new Class[]{int.class,double.class},23,0d);waitFor(()->page()==23);long timestamp=saved().updatedAt;
        invoke("bookmarks",new Class[]{});click("打开书签 11");waitFor(()->page()==10);assertTrue((boolean)field(activity,"temporary"));assertEquals(23,saved().locator.page);assertEquals(timestamp,saved().updatedAt);
        invoke("navigate",new Class[]{int.class,double.class},12,0d);waitFor(()->page()==12);assertEquals(timestamp,saved().updatedAt);
        instrument.runOnMainSync(()->((android.widget.Button)field(activity,"returnToReading")).performClick());waitFor(()->page()==23);assertFalse((boolean)field(activity,"temporary"));assertEquals(timestamp,saved().updatedAt);
        ComicPageView view=(ComicPageView)field(activity,"pageView");instrument.runOnMainSync(()->{view.zoomBy(1.25f);view.fitWidth(false);});assertEquals(timestamp,saved().updatedAt);
        invoke("bookmarks",new Class[]{});click("删除书签 11");click("删除");click("关闭");try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertTrue(db.documentBookmarks(book.id).isEmpty());}
        long unchanged=saved().updatedAt;android.app.Instrumentation.ActivityMonitor monitor=instrument.addMonitor(ComicPreviewActivity.class.getName(),null,false);instrument.runOnMainSync(()->activity.setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));activity=(ComicPreviewActivity)instrument.waitForMonitorWithTimeout(monitor,10000);instrument.removeMonitor(monitor);assertNotNull(activity);waitFor(()->page()==23&&!(boolean)field(activity,"opening"));assertEquals(unchanged,saved().updatedAt);
        File cache=(File)field(activity,"directory");finish();assertFalse(cache.exists());launch();assertEquals(23,page());assertEquals(timestamp,saved().updatedAt);assertArrayEquals(original,Files.readAllBytes(source.toPath()));
        invoke("menus",new Class[]{boolean.class},true);assertFalse(find(instrument.getUiAutomation().getRootInActiveWindow(),"搜索").isEnabled());assertTrue(find(instrument.getUiAutomation().getRootInActiveWindow(),"书签").isEnabled());screenshot("comic-formal-menu.png");click("切换阅读主题");screenshot("comic-formal-menu-toggled.png");assertEquals(timestamp,saved().updatedAt);
    }
    @Test public void corruptedArchiveAndCancelledImportNeverPublishOrKeepTemporaryFiles()throws Exception {
        File broken=fixture("comic-basic-rar4-solid.cbr");try(RandomAccessFile raw=new RandomAccessFile(broken,"rw")){raw.setLength(raw.length()/2);}assertThrows(IOException.class,()->new NativeComicArchive(broken,ComicArchive.NEVER));
        File valid=fixture("comic-basic-rar5.cbr");assertThrows(IOException.class,()->new NativeComicArchive(valid,()->true));
        File zip=File.createTempFile("unsafe-",".cbz",context.getCacheDir());files.add(zip);try(ZipOutputStream out=new ZipOutputStream(new FileOutputStream(zip))){out.putNextEntry(new ZipEntry("../escape.png"));out.write(new byte[]{1});out.closeEntry();}assertThrows(IOException.class,()->new NativeComicArchive(zip,ComicArchive.NEVER));assertFalse(new File(context.getCacheDir(),"escape.png").exists());
        File imports=new File(context.getCacheDir(),"cancelled-comic-import");imports.mkdirs();int[] published={0},failed={0};BookImportController<File> controller=new BookImportController<>(imports,new BookImportController.Source<File>(){public String name(File f){return "cancel.cbr";}public InputStream open(File f)throws Exception{return new FileInputStream(f);}public void validate(File f,String format,ComicArchive.Cancellation cancel)throws Exception{DocumentFormats.validate(context,f,format,()->true);}},Runnable::run,Runnable::run,new BookImportController.Listener(){public void changed(){}public void publish(Book b){published[0]++;}public void finished(int a,int d,int f){failed[0]=f;}});controller.importBooks(Collections.singletonList(valid),Collections.emptyList());assertEquals(0,published[0]);assertEquals(1,failed[0]);assertEquals(0,imports.list().length);controller.close();imports.delete();
    }
}
