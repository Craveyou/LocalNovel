package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Activity;
import android.app.Instrumentation;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.webkit.WebView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import com.tom_roush.pdfbox.pdmodel.PDPage;
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream;
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission;
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy;
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/** Runs only on a disposable emulator: resets the target's local test book library. */
@RunWith(AndroidJUnit4.class)
public class DocumentReaderDeviceTest {
    private final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    private Context context;
    private LocalDatabase database;
    private DocumentReaderActivity activity;
    @Before public void setup() throws Exception {
        assertTrue("Use a disposable emulator",android.os.Build.HARDWARE.contains("ranchu")||android.os.Build.HARDWARE.contains("goldfish"));
        PdfCropSettings.reset();
        context=instrument.getTargetContext();context.deleteDatabase("xlib.db");
        context.getSharedPreferences("xlib_reader",0).edit().clear().commit();
        database=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0));
        PDFBoxResourceLoader.init(context);
    }
    @After public void cleanup()throws Exception{if(activity!=null){instrument.runOnMainSync(()->activity.finish());instrument.waitForIdleSync();waitFor(()->((java.util.concurrent.ExecutorService)field(activity,"worker")).isTerminated());}if(database!=null)database.close();}
    private static Object field(Object o,String key){try{Field f=o.getClass().getDeclaredField(key);f.setAccessible(true);return f.get(o);}catch(Exception e){throw new AssertionError(e);}}
    private void waitFor(BooleanSupplier check)throws Exception{
        long end=SystemClock.uptimeMillis()+20_000;
        while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();if(check.getAsBoolean())return;Thread.sleep(40);}
        throw new AssertionError("Reader operation timed out");
    }
    private void launch(Book b)throws Exception{
        activity=(DocumentReaderActivity)instrument.startActivitySync(new Intent(context,DocumentReaderActivity.class).putExtra("bookId",b.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        // Password/error dialogs legitimately own focus while opening. Only
        // require the body to own focus when sending a body gesture in click().
        instrument.waitForIdleSync();Thread.sleep(350);
    }
    private Book save(File file,String format)throws Exception{
        Book b=new Book();b.id=991;b.title=b.sourceName="device-test."+format;b.format=format;b.encoding="UTF-8";b.path=file.getAbsolutePath();b.fileSize=file.length();
        assertTrue(database.saveBooks(List.of(b),null,0,0));return b;
    }
    private void screenshot(String name)throws Exception{Thread.sleep(350);Bitmap image=instrument.getUiAutomation().takeScreenshot();try(java.io.FileOutputStream out=new java.io.FileOutputStream(new File(context.getExternalFilesDir(null),name))){assertTrue(image.compress(Bitmap.CompressFormat.PNG,100,out));}image.recycle();}
    private void click(String label)throws Exception{
        long end=SystemClock.uptimeMillis()+8000;
        boolean revealed=false;
        while(SystemClock.uptimeMillis()<end){
            AccessibilityNodeInfo root=instrument.getUiAutomation().getRootInActiveWindow();
            if(root!=null)for(AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(label)){
                if(!label.contentEquals(node.getText()==null?"":node.getText()))continue;
                AccessibilityNodeInfo target=node;
                while(target!=null&&!target.isClickable())target=target.getParent();
                if(target!=null&&target.performAction(AccessibilityNodeInfo.ACTION_CLICK)){instrument.waitForIdleSync();return;}
            }
            AccessibilityNodeInfo described=byDescription(root,label);
            if(described!=null&&described.performAction(AccessibilityNodeInfo.ACTION_CLICK)){instrument.waitForIdleSync();return;}
            if(!revealed&&activity!=null&&activity.hasWindowFocus()&&field(activity,"readerChrome")!=null&&!(boolean)field(activity,"readerMenusOpen")){
                revealed=true;View page=(View)(field(activity,"epubView")!=null?field(activity,"epubView"):field(activity,"pdfView"));int[] xy=new int[2];instrument.runOnMainSync(()->page.getLocationOnScreen(xy));
                long down=SystemClock.uptimeMillis();sendPointer(down,MotionEvent.ACTION_DOWN,xy[0]+page.getWidth()*.45f,xy[1]+page.getHeight()/2f);sendPointer(down,MotionEvent.ACTION_UP,xy[0]+page.getWidth()*.45f,xy[1]+page.getHeight()/2f);
                Thread.sleep(android.view.ViewConfiguration.getDoubleTapTimeout()+80);
            }
            Thread.sleep(50);
        }
        throw new AssertionError("Missing control: "+label);
    }
    private AccessibilityNodeInfo byDescription(AccessibilityNodeInfo node,String label){
        if(node==null)return null;if(label.contentEquals(node.getContentDescription()==null?"":node.getContentDescription()))return node;
        for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo found=byDescription(node.getChild(i),label);if(found!=null)return found;}return null;
    }
    private void input(String value)throws Exception{
        AccessibilityNodeInfo root=instrument.getUiAutomation().getRootInActiveWindow();
        assertNotNull(root);assertTrue(fill(root,value));
    }
    private boolean fill(AccessibilityNodeInfo node,String value){
        if(node.isEditable()){Bundle args=new Bundle();args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,value);return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,args);}
        for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo child=node.getChild(i);if(child!=null&&fill(child,value))return true;}return false;
    }
    private String js(String script)throws Exception{
        CountDownLatch done=new CountDownLatch(1);AtomicReference<String> value=new AtomicReference<>();
        instrument.runOnMainSync(()->((WebView)field(activity,"epubView")).evaluateJavascript(script,result->{value.set(result);done.countDown();}));
        assertTrue(done.await(10,TimeUnit.SECONDS));return value.get();
    }
    private void entry(ZipOutputStream zip,String path,String text)throws Exception{zip.putNextEntry(new ZipEntry(path));zip.write(text.getBytes(StandardCharsets.UTF_8));zip.closeEntry();}
    private File epub()throws Exception{
        File dir=new File(context.getFilesDir(),"books");dir.mkdirs();File file=new File(dir,"991-device.epub");
        try(ZipOutputStream zip=new ZipOutputStream(new FileOutputStream(file))){
            entry(zip,"mimetype","application/epub+zip");
            entry(zip,"META-INF/container.xml","<container xmlns='urn:oasis:names:tc:opendocument:xmlns:container'><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>");
            entry(zip,"OPS/book.opf","<package xmlns='http://www.idpf.org/2007/opf' version='3.0'><manifest><item id='z' href='z.xhtml' media-type='application/xhtml+xml'/><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='nav' href='nav.xhtml' media-type='application/xhtml+xml' properties='nav'/></manifest><spine><itemref idref='z'/><itemref idref='a'/></spine></package>");
            StringBuilder body=new StringBuilder("<h1 id='start'>第一章</h1><img src='pixel.png'/>");
            for(int i=0;i<100;i++)body.append("<p id='p").append(i).append("'>继续阅读👩‍💻，中文、é与&nbsp;空白。段落 ").append(i).append("</p>");
            entry(zip,"OPS/z.xhtml","<html xmlns='http://www.w3.org/1999/xhtml'><head><link rel='stylesheet' href='local.css'/></head><body>"+body+"<script>window.xlibAuthoredScript=true</script></body></html>");
            entry(zip,"OPS/a.xhtml","<html xmlns='http://www.w3.org/1999/xhtml'><body><h1>第二章</h1><p>另一章正文</p></body></html>");
            entry(zip,"OPS/local.css","p{margin-bottom:12px}h1{font-weight:bold}");
            entry(zip,"OPS/nav.xhtml","<html xmlns='http://www.w3.org/1999/xhtml' xmlns:epub='http://www.idpf.org/2007/ops'><body><nav epub:type='toc'><a href='z.xhtml#start'>第一章</a><a href='a.xhtml'>第二章</a></nav></body></html>");
            zip.putNextEntry(new ZipEntry("OPS/pixel.png"));Bitmap bitmap=Bitmap.createBitmap(2,2,Bitmap.Config.ARGB_8888);bitmap.eraseColor(0xff228855);bitmap.compress(Bitmap.CompressFormat.PNG,100,zip);bitmap.recycle();zip.closeEntry();
        }
        return file;
    }
    @Test public void epubRunsOfflineReflowsCopiesAndRestoresTypedPosition()throws Exception{
        Book b=save(epub(),"epub");
        try(EpubDocument source=new EpubDocument(context,new File(b.path))){assertEquals(2,source.chapters.size());}
        launch(b);
        try{waitFor(()->field(activity,"sync")!=null);}catch(AssertionError failure){
            if(field(activity,"epubView")!=null)throw new AssertionError("EPUB bridge: "+js("JSON.stringify({title:document.title,token:document.documentElement.getAttribute('data-xlib-generation'),nodes:window.xlibNodes&&window.xlibNodes.length,text:document.body.textContent.substring(0,160),length:document.body.textContent.length})"),failure);
            throw failure;
        }
        assertEquals("true",js("document.images[0].complete && document.images[0].naturalWidth > 0"));
        assertEquals("true",js("typeof window.xlibAuthoredScript === 'undefined'"));
        assertEquals("true",js("parseFloat(getComputedStyle(document.querySelector('p')).lineHeight)>parseFloat(getComputedStyle(document.querySelector('p')).fontSize)"));
        assertEquals(0,database.loadBooks().get(0).updatedAt);
        DocumentLocator original=database.loadBooks().get(0).locator;
        float before=new ReadingPreferences(database).readingFontSize();
        click("排版");screenshot("modern-epub-formatting.png");click("增大字号");screenshot("modern-epub-menu.png");waitFor(()->field(activity,"position").equals(original)&&field(activity,"sync")!=null);
        waitFor(()->new ReadingPreferences(database).readingFontSize()>before&&field(field(activity,"epubView"),"completion")==null);
        assertEquals(original,database.loadBooks().get(0).locator);assertEquals(0,database.loadBooks().get(0).updatedAt);
        assertEquals("true",js("parseFloat(getComputedStyle(document.querySelector('p')).fontSize)>"+before));
        click("书签");click("添加当前位置");click("确定");assertEquals(1,database.documentBookmarks(b.id).size());
        js("(function(){var n=window.xlibNodes.find(function(n){return n.data.indexOf('继续')>=0;});var r=document.createRange();r.setStart(n,0);r.setEnd(n,2);var s=window.getSelection();s.removeAllRanges();s.addRange(r);})()");
        waitFor(()->!((String)field(activity,"epubSelection")).isEmpty());click("复制");
        AtomicReference<String> clipboard=new AtomicReference<>();instrument.runOnMainSync(()->clipboard.set(((ClipboardManager)context.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString()));
        assertEquals("继续",clipboard.get());assertEquals(0,database.loadBooks().get(0).updatedAt);
        click("下一章");waitFor(()->database.loadBooks().get(0).locator.spineIndex==1);
        long time=database.loadBooks().get(0).updatedAt;assertTrue(time>0);
        instrument.runOnMainSync(()->activity.finish());instrument.waitForIdleSync();launch(database.loadBooks().get(0));waitFor(()->field(activity,"sync")!=null);
        assertEquals(1,((DocumentLocator)field(activity,"position")).spineIndex);assertEquals(time,database.loadBooks().get(0).updatedAt);
    }
    private File pdf()throws Exception{return pdf(true);}
    private File pdf(boolean encrypted)throws Exception{
        File dir=new File(context.getFilesDir(),"books");dir.mkdirs();File file=new File(dir,"991-device.pdf");
        try(PDDocument doc=new PDDocument()){
            for(int i=0;i<3;i++){PDPage page=new PDPage();doc.addPage(page);try(PDPageContentStream out=new PDPageContentStream(doc,page)){out.beginText();out.setFont(PDType1Font.HELVETICA,20);out.newLineAtOffset(40,700);out.showText("Hello original page "+(i+1));out.endText();}}
            if(encrypted){StandardProtectionPolicy protection=new StandardProtectionPolicy("owner-fixture-only","reader-fixture-only",new AccessPermission());protection.setEncryptionKeyLength(128);doc.protect(protection);}
            doc.save(file);
        }
        return file;
    }
    @Test public void pdfLongPressContinuesDraggingAndCopiesWithoutReadingEvent()throws Exception{
        Book b=save(pdf(false),"pdf");launch(b);waitFor(()->field(activity,"sync")!=null);
        PdfPageView view=(PdfPageView)field(activity,"pdfView");
        java.lang.reflect.Method geometry=PdfPageView.class.getDeclaredMethod("box",int.class);geometry.setAccessible(true);
        AtomicReference<android.graphics.RectF> first=new AtomicReference<>(),last=new AtomicReference<>();int[] screen=new int[2];
        instrument.runOnMainSync(()->{try{view.getLocationOnScreen(screen);first.set((android.graphics.RectF)geometry.invoke(view,1));last.set((android.graphics.RectF)geometry.invoke(view,18));}catch(Exception e){throw new AssertionError(e);}});
        long down=SystemClock.uptimeMillis();
        sendPointer(down,MotionEvent.ACTION_DOWN,screen[0]+first.get().centerX(),screen[1]+first.get().centerY());
        Thread.sleep(android.view.ViewConfiguration.getLongPressTimeout()+150);
        waitFor(view::hasSelection);String word=view.selectedText();assertEquals("Hello",word);
        sendPointer(down,MotionEvent.ACTION_MOVE,screen[0]+last.get().centerX(),screen[1]+last.get().centerY());
        sendPointer(down,MotionEvent.ACTION_UP,screen[0]+last.get().centerX(),screen[1]+last.get().centerY());
        waitFor(()->view.selectedText().length()>word.length());String selected=view.selectedText();assertTrue(selected.startsWith("Hello original"));
        click("复制");AtomicReference<String> clip=new AtomicReference<>();instrument.runOnMainSync(()->clip.set(((ClipboardManager)context.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString()));
        assertEquals(selected,clip.get());assertEquals(0,database.loadBooks().get(0).updatedAt);assertEquals(0,database.loadBooks().get(0).locator.page);
    }
    @Test public void epubThemeAndKeepAwakePersistWithoutChangingReadingProgress()throws Exception{
        ReadingPreferences preferences=new ReadingPreferences(database);preferences.setReadingKeepScreenOn(true);
        Book b=save(epub(),"epub");launch(b);waitFor(()->field(activity,"sync")!=null);
        int flag=android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON;
        instrument.runOnMainSync(()->assertNotEquals(0,activity.getWindow().getAttributes().flags&flag));
        click("排版");click("深色正文");
        waitFor(()->preferences.appTheme()==ReaderSettingsOptions.THEME_DARK);
        // Real WebView computed style confirms the persisted theme was applied to content.
        waitFor(()->{try{return "\"rgb(16, 19, 18)\"".equals(js("getComputedStyle(document.documentElement).backgroundColor"));}catch(Exception failure){throw new AssertionError(failure);}});
        assertEquals(0,database.loadBooks().get(0).updatedAt);
        java.util.concurrent.ExecutorService previous=(java.util.concurrent.ExecutorService)field(activity,"worker");
        instrument.runOnMainSync(()->activity.finish());assertTrue(previous.awaitTermination(10,TimeUnit.SECONDS));
        launch(database.loadBooks().get(0));waitFor(()->field(activity,"sync")!=null);
        assertTrue((boolean)field(activity,"dark"));
        assertEquals("\"rgb(16, 19, 18)\"",js("getComputedStyle(document.documentElement).backgroundColor"));
        instrument.runOnMainSync(()->assertNotEquals(0,activity.getWindow().getAttributes().flags&flag));
        assertEquals(0,database.loadBooks().get(0).updatedAt);
    }
    @Test public void pdfSearchCanStopAndRestartFromBookBeginningWithoutMovingFormalPosition()throws Exception{
        Book b=save(pdf(false),"pdf");launch(b);waitFor(()->field(activity,"sync")!=null);
        click("下一页");waitFor(()->database.loadBooks().get(0).locator.page==1);
        long readAt=database.loadBooks().get(0).updatedAt;
        java.util.concurrent.ExecutorService worker=(java.util.concurrent.ExecutorService)field(activity,"worker");
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        worker.execute(()->{entered.countDown();try{release.await();}catch(InterruptedException ignored){Thread.currentThread().interrupt();}});
        assertTrue(entered.await(5,TimeUnit.SECONDS));
        try{
            click("搜索");screenshot("modern-pdf-search.png");input("Hello");click("从书首搜索");click("搜索");
            click("停止搜索");waitFor(()->field(activity,"search")==null);
        }finally{release.countDown();}
        worker.submit(()->{}).get(10,TimeUnit.SECONDS);
        click("搜索");screenshot("modern-pdf-search.png");input("Hello");click("从书首搜索");click("搜索");
        waitFor(()->!(boolean)field(activity,"searching"));
        List<DocumentSearch.Hit> hits=(List<DocumentSearch.Hit>)field(activity,"searchHits");
        assertEquals(3,hits.size());assertEquals(0,hits.get(0).locator.page);
        assertTrue(((DocumentSearch)field(activity,"search")).complete);
        click("关闭");assertEquals(1,database.loadBooks().get(0).locator.page);assertEquals(readAt,database.loadBooks().get(0).updatedAt);
    }
    @Test public void damagedPdfAndEpubRetryInPlaceAndRestorePositionTimeAndBookmarks()throws Exception{
        for(String format:new String[]{"pdf","epub"}) {
            Book b=save("pdf".equals(format)?pdf(false):epub(),format);
            launch(b);waitFor(()->field(activity,"sync")!=null);
            click("pdf".equals(format)?"下一页":"下一章");
            waitFor(()->database.loadBooks().get(0).updatedAt>0);
            Book saved=database.loadBooks().get(0);
            assertTrue(database.addDocumentBookmark(b.id,saved.locator));
            java.util.concurrent.ExecutorService previous=(java.util.concurrent.ExecutorService)field(activity,"worker");
            instrument.runOnMainSync(()->activity.finish());assertTrue(previous.awaitTermination(10,TimeUnit.SECONDS));
            File file=new File(b.path);
            byte[] original=java.nio.file.Files.readAllBytes(file.toPath());
            java.nio.file.Files.write(file.toPath(),"interrupted source".getBytes(StandardCharsets.UTF_8));
            launch(saved);click("重试打开");
            waitFor(()->!(boolean)field(activity,"opening"));
            assertFalse((boolean)field(activity,"ready"));assertNull(field(activity,"sync"));
            assertFalse(activity.isFinishing());
            assertEquals(saved.locator,database.loadBooks().get(0).locator);
            assertEquals(saved.updatedAt,database.loadBooks().get(0).updatedAt);
            java.nio.file.Files.write(file.toPath(),original);
            click("重试打开");waitFor(()->field(activity,"sync")!=null);
            assertEquals(saved.locator,field(activity,"position"));
            assertEquals(saved.updatedAt,database.loadBooks().get(0).updatedAt);
            assertEquals(1,database.documentBookmarks(b.id).size());
            previous=(java.util.concurrent.ExecutorService)field(activity,"worker");
            instrument.runOnMainSync(()->activity.finish());assertTrue(previous.awaitTermination(10,TimeUnit.SECONDS));activity=null;
            database.deleteBook(saved);
        }
    }
    private void sendPointer(long down,int action,float x,float y){MotionEvent event=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);instrument.sendPointerSync(event);event.recycle();}
    @Test public void pdfPasswordRetryNavigationAndReopenKeepOnlyOriginalFile()throws Exception{
        Book b=save(pdf(),"pdf");launch(b);waitFor(()->!(boolean)field(activity,"ready"));
        waitFor(()->{AccessibilityNodeInfo root=instrument.getUiAutomation().getRootInActiveWindow();return root!=null&&!root.findAccessibilityNodeInfosByText("此 PDF 需要密码").isEmpty();});input("wrong");click("打开");
        waitFor(()->{AccessibilityNodeInfo root=instrument.getUiAutomation().getRootInActiveWindow();return root!=null&&!root.findAccessibilityNodeInfosByText("密码错误，请重试").isEmpty();});
        assertEquals(0,database.loadBooks().get(0).updatedAt);input("reader-fixture-only");click("打开");
        waitFor(()->field(activity,"sync")!=null);assertEquals(0,database.loadBooks().get(0).updatedAt);
        click("下一页");waitFor(()->database.loadBooks().get(0).locator.page==1);long time=database.loadBooks().get(0).updatedAt;assertTrue(time>0);
        instrument.runOnMainSync(()->activity.finish());instrument.waitForIdleSync();launch(database.loadBooks().get(0));
        waitFor(()->{AccessibilityNodeInfo root=instrument.getUiAutomation().getRootInActiveWindow();return root!=null&&!root.findAccessibilityNodeInfosByText("此 PDF 需要密码").isEmpty();});
        assertEquals(1,database.loadBooks().get(0).locator.page);assertEquals(time,database.loadBooks().get(0).updatedAt);
        input("reader-fixture-only");click("打开");waitFor(()->field(activity,"sync")!=null);
        assertEquals(1,((DocumentLocator)field(activity,"position")).page);assertEquals(time,database.loadBooks().get(0).updatedAt);
        assertThrows(com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException.class,()->new PdfDocument(context,new File(b.path),null));
    }
}
