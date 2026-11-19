package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Instrumentation;
import android.content.*;
import android.os.*;
import android.graphics.Bitmap;
import android.view.View;
import android.webkit.WebView;
import android.widget.Button;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class KindleDeviceTest {
    static final String[] NAMES={"kindle-mobi6.mobi","kindle-palmdoc.azw","kindle-huff.mobi","kindle-kf8.azw3","kindle-mixed.mobi","kindle-long.mobi"};
    final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    final Context context=instrument.getTargetContext();
    DocumentReaderActivity activity;
    static Object field(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    File original(String name)throws Exception{File file=new File(context.getCacheDir(),name);try(InputStream input=instrument.getContext().getAssets().open("documents/"+name);OutputStream out=new FileOutputStream(file)){byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1)out.write(buffer,0,n);}return file;}
    JSONObject expected(String name)throws Exception{try(InputStream input=instrument.getContext().getAssets().open("documents/"+name+".json")){ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1)out.write(buffer,0,n);return new JSONObject(out.toString("UTF-8"));}}
    void jsonEquals(Object a,Object b)throws Exception{if(a instanceof JSONObject&&b instanceof JSONObject){JSONObject x=(JSONObject)a,y=(JSONObject)b;assertEquals(x.length(),y.length());for(Iterator<String> keys=x.keys();keys.hasNext();){String key=keys.next();jsonEquals(x.get(key),y.get(key));}}else if(a instanceof JSONArray&&b instanceof JSONArray){JSONArray x=(JSONArray)a,y=(JSONArray)b;assertEquals(x.length(),y.length());for(int i=0;i<x.length();i++)jsonEquals(x.get(i),y.get(i));}else assertEquals(a,b);}
    @Test public void sharedCoreParityAllSixOriginalPublicationsAndSafeResources()throws Exception {
        for(String name:NAMES){File file=original(name);JSONObject expected=expected(name);java.security.MessageDigest digest=java.security.MessageDigest.getInstance("SHA-256");try(InputStream input=new FileInputStream(file)){byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1)digest.update(buffer,0,n);}StringBuilder hash=new StringBuilder();for(byte b:digest.digest())hash.append(String.format(Locale.ROOT,"%02x",b&255));String sourceHash=hash.toString();
            assertEquals(name,expected.getString("sha256"),sourceHash);
            try(KindleDocument doc=new KindleDocument(context,file,ComicArchive.NEVER)){
                assertEquals(expected.getString("canonicalText"),doc.canonicalText);assertEquals(expected.getString("textHash"),doc.textHash);assertEquals(expected.getString("mode"),doc.mode);assertEquals(expected.optString("coverResource",null),doc.coverResource);
                jsonEquals(expected.getJSONArray("toc"),doc.output.getJSONArray("toc"));JSONArray units=expected.getJSONArray("chapters");
                for(int i=0;i<units.length();i++){JSONObject want=units.getJSONObject(i),actual=doc.output.getJSONArray("chapters").getJSONObject(i);for(Iterator<String> keys=want.keys();keys.hasNext();){String key=keys.next();jsonEquals(want.get(key),actual.get(key));}assertTrue(doc.valid(doc.locator(i,0)));}
                assertThrows(IOException.class,()->doc.read("../unsafe"));if(doc.coverResource!=null)assertTrue(doc.read(doc.coverResource).length>0);
                DocumentLocator start=doc.locator(0,0);assertFalse(doc.valid(DocumentLocator.kindle("00".repeat(32),0,start.textLength)));
                assertThrows(IOException.class,()->new KindleDocument(context,file,()->true));
            }
        }
    }
    void waitReady()throws Exception{long end=SystemClock.uptimeMillis()+45000;while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();if((boolean)field(activity,"ready")&&!(boolean)field(activity,"opening"))return;Thread.sleep(50);}fail("Kindle reader failed to become ready");}
    void invoke(String method,Class<?>[] types,Object...args){instrument.runOnMainSync(()->{try{Method m=DocumentReaderActivity.class.getDeclaredMethod(method,types);m.setAccessible(true);m.invoke(activity,args);}catch(Exception e){throw new AssertionError(e);}});}
    Object js(String script)throws Exception{CountDownLatch done=new CountDownLatch(1);String[] result={null};instrument.runOnMainSync(()->{try{((WebView)field(activity,"epubView")).evaluateJavascript(script,value->{result[0]=value;done.countDown();});}catch(Exception e){throw new AssertionError(e);}});assertTrue(done.await(10,TimeUnit.SECONDS));return new JSONTokener(result[0]).nextValue();}
    void go(DocumentLocator target,boolean user)throws Exception{invoke("navigate",new Class<?>[]{DocumentLocator.class,boolean.class},target,user);long end=SystemClock.uptimeMillis()+15000;while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();if(target.equals(field(activity,"position"))){try{KindleDocument doc=(KindleDocument)field(activity,"epub");if(doc.chapters.get(doc.chapterIndex(target)).text.equals(js("window.xlibText")))return;}catch(Exception ignored){}}Thread.sleep(50);}fail("navigation did not complete");}
    void waitRendered()throws Exception{long end=SystemClock.uptimeMillis()+15000;while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();Object view=field(activity,"epubView");if(view!=null&&field(view,"completion")==null){try{KindleDocument doc=(KindleDocument)field(activity,"epub");DocumentLocator p=(DocumentLocator)field(activity,"position");if(doc.chapters.get(doc.chapterIndex(p)).text.equals(js("window.xlibText")))return;}catch(Exception ignored){}}Thread.sleep(50);}fail("reflow render did not finish");}
    @After public void close()throws Exception{if(activity!=null){instrument.runOnMainSync(activity::finish);long end=SystemClock.uptimeMillis()+10000;while(!activity.isDestroyed()&&SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();Thread.sleep(30);}assertTrue(activity.isDestroyed());ExecutorService worker=(ExecutorService)field(activity,"worker");assertTrue(worker.awaitTermination(10,TimeUnit.SECONDS));}}
    @Test public void importReadSearchSelectionBookmarksReflowAndReopen()throws Exception {
        File source=original("kindle-mobi6.mobi");List<Book> published=new ArrayList<>();File directory=new File(context.getFilesDir(),"books");directory.mkdirs();
        BookImportController<File> controller=new BookImportController<>(directory,new BookImportController.Source<File>(){
            public String name(File f){return "阅读测试.MOBI";}public InputStream open(File f)throws Exception{return new FileInputStream(f);}public void validate(File f,String format,ComicArchive.Cancellation cancel)throws Exception{DocumentFormats.validate(context,f,format,cancel);}
        },Runnable::run,Runnable::run,new BookImportController.Listener(){public void changed(){}public void publish(Book b){published.add(b);}public void finished(int a,int d,int f){assertEquals(1,a);assertEquals(0,f);}});
        controller.importBooks(Collections.singletonList(source),Collections.emptyList());controller.close();assertEquals(1,published.size());Book book=published.get(0);assertEquals("kindle",book.format);
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){List<Book> books=db.loadBooks();books.add(book);assertTrue(db.saveBooks(books,null,0,0));}
        Bitmap cover=KindleCoverCache.load(context,book);assertNotNull(cover);assertTrue(Math.max(cover.getWidth(),cover.getHeight())<=256);cover.recycle();
        activity=(DocumentReaderActivity)instrument.startActivitySync(new Intent(context,DocumentReaderActivity.class).putExtra("bookId",book.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));waitReady();
        KindleDocument doc=(KindleDocument)field(activity,"epub");assertEquals(doc.chapters.get(0).text,js("window.xlibNodes.map(n=>n.data).join('')"));
        go(doc.locator(1,0),false);
        assertTrue(((Number)js("document.images.length")).intValue()>0);assertEquals(Boolean.TRUE,js("Array.from(document.images).every(i=>i.complete&&i.naturalWidth>0)"));
        DocumentLocator initial=(DocumentLocator)field(activity,"formal");long time=(long)field(activity,"readAt");assertEquals(0,time);
        // Programmatic layout/selection does not manufacture a reading event.
        invoke("resizeContent",new Class<?>[]{int.class},1);waitRendered();assertEquals(initial,field(activity,"formal"));assertEquals(time,field(activity,"readAt"));
        JSONObject rect=(JSONObject)js("(function(){var n=window.xlibNodes.find(n=>n.data.indexOf('你好')>=0),r=document.createRange();r.setStart(n,0);r.setEnd(n,2);var b=r.getBoundingClientRect();return {x:(b.left+b.right)/2,y:(b.top+b.bottom)/2};})()");
        int[] origin=new int[2];instrument.runOnMainSync(()->{try{((WebView)field(activity,"epubView")).getLocationOnScreen(origin);}catch(Exception e){throw new AssertionError(e);}});
        float density=context.getResources().getDisplayMetrics().density,x=origin[0]+(float)rect.getDouble("x")*density,y=origin[1]+(float)rect.getDouble("y")*density;
        long down=SystemClock.uptimeMillis();android.view.MotionEvent press=android.view.MotionEvent.obtain(down,down,0,x,y,0);instrument.sendPointerSync(press);press.recycle();Thread.sleep(850);android.view.MotionEvent up=android.view.MotionEvent.obtain(down,SystemClock.uptimeMillis(),1,x,y,0);instrument.sendPointerSync(up);up.recycle();
        long selectedEnd=SystemClock.uptimeMillis()+5000;while(((String)field(activity,"epubSelection")).isEmpty()&&SystemClock.uptimeMillis()<selectedEnd){instrument.waitForIdleSync();Thread.sleep(30);}assertFalse("native long press selects canonical text",((String)field(activity,"epubSelection")).isEmpty());
        assertEquals(View.VISIBLE,((View)field(activity,"selectionBar")).getVisibility());assertEquals(initial,field(activity,"formal"));assertEquals(time,field(activity,"readAt"));
        android.app.UiAutomation automation=instrument.getUiAutomation();android.view.accessibility.AccessibilityNodeInfo root=null;long windowEnd=SystemClock.uptimeMillis()+5000;while(root==null&&SystemClock.uptimeMillis()<windowEnd){root=automation.getRootInActiveWindow();if(root==null)Thread.sleep(50);}assertNotNull("reader accessibility window is available",root);assertTrue(root.findAccessibilityNodeInfosByText("Select all").isEmpty());assertTrue(root.findAccessibilityNodeInfosByText("全选").isEmpty());root.recycle();
        Bitmap screen=instrument.getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),"kindle-selection.png"))){assertTrue(screen.compress(Bitmap.CompressFormat.PNG,100,out));}screen.recycle();
        invoke("clearSelection",new Class<?>[]{});
        int emoji=doc.chapters.get(1).text.indexOf("😀");assertTrue(emoji>=0);
        instrument.runOnMainSync(()->{try{((EpubPageView)field(activity,"epubView")).highlight(emoji,2);}catch(Exception e){throw new AssertionError(e);}});Thread.sleep(500);assertEquals("😀",field(activity,"epubSelection"));assertEquals(time,field(activity,"readAt"));
        instrument.runOnMainSync(()->{try{((Button)field(activity,"copy")).performClick();}catch(Exception e){throw new AssertionError(e);}});assertEquals("😀",((ClipboardManager)context.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString());
        instrument.runOnMainSync(()->{try{((EpubPageView)field(activity,"epubView")).highlight(0,doc.chapters.get(1).text.length());}catch(Exception e){throw new AssertionError(e);}});Thread.sleep(300);
        assertEquals(doc.chapters.get(1).text.replace("\ufffc", ""),field(activity,"epubSelection"));invoke("clearSelection",new Class<?>[]{});
        invoke("beginSearch",new Class<?>[]{String.class,boolean.class},"你好",true);
        long searchEnd=SystemClock.uptimeMillis()+10000;while((boolean)field(activity,"searching")&&SystemClock.uptimeMillis()<searchEnd){instrument.waitForIdleSync();Thread.sleep(30);}
        assertFalse((boolean)field(activity,"searching"));assertFalse(((List<?>)field(activity,"searchHits")).isEmpty());
        instrument.runOnMainSync(()->{try{android.app.AlertDialog dialog=(android.app.AlertDialog)field(activity,"searchDialog");dialog.getListView().performItemClick(null,0,0);}catch(Exception e){throw new AssertionError(e);}});waitRendered();assertTrue((boolean)field(activity,"temporary"));assertEquals(initial,field(activity,"formal"));assertEquals(time,field(activity,"readAt"));
        instrument.runOnMainSync(()->{try{((Button)field(activity,"returnToReading")).performClick();}catch(Exception e){throw new AssertionError(e);}});waitRendered();assertFalse((boolean)field(activity,"temporary"));assertEquals(initial,field(activity,"formal"));assertEquals(time,field(activity,"readAt"));
        DocumentLocator target=doc.locator(Math.min(1,doc.chapters.size()-1),0);go(target,true);
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertTrue(db.addDocumentBookmark(book.id,target));assertFalse(db.addDocumentBookmark(book.id,target));assertEquals(target,db.documentBookmarks(book.id).get(0).locator);assertTrue((long)field(activity,"readAt")>0);}
        close();activity=null;activity=(DocumentReaderActivity)instrument.startActivitySync(new Intent(context,DocumentReaderActivity.class).putExtra("bookId",book.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));waitReady();assertEquals(target,field(activity,"formal"));
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){LocalDatabase.DocumentBookmark bookmark=db.documentBookmarks(book.id).get(0);db.deleteDocumentBookmark(book.id,bookmark.id);assertTrue(db.documentBookmarks(book.id).isEmpty());}
    }
}
