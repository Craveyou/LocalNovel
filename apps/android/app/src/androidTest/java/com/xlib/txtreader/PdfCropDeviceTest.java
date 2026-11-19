package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Instrumentation;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.RectF;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import com.tom_roush.pdfbox.pdmodel.PDPage;
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream;
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font;
import java.io.File;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Run twice in separate instrumentation processes to verify process-restart defaults. */
@RunWith(AndroidJUnit4.class)
public class PdfCropDeviceTest {
    private final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    private DocumentReaderActivity activity;
    private static Object field(Object object,String name)throws Exception{Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object);}
    private void waitFor(BooleanSupplier check)throws Exception{
        long deadline=SystemClock.uptimeMillis()+20000;
        while(SystemClock.uptimeMillis()<deadline){instrument.waitForIdleSync();if(check.getAsBoolean())return;Thread.sleep(40);}
        fail("Crop reader operation timed out");
    }
    private void ready()throws Exception{waitFor(()->{try{return field(activity,"sync")!=null;}catch(Exception e){throw new AssertionError(e);}});}
    private void launch(Context context,Book book)throws Exception{
        activity=(DocumentReaderActivity)instrument.startActivitySync(new Intent(context,DocumentReaderActivity.class).putExtra("bookId",book.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));ready();waitFor(activity::hasWindowFocus);Thread.sleep(350);
    }
    private void finish()throws Exception{
        if(activity==null)return;ExecutorService worker=(ExecutorService)field(activity,"worker");
        instrument.runOnMainSync(()->activity.finish());assertTrue(worker.awaitTermination(10,TimeUnit.SECONDS));instrument.waitForIdleSync();activity=null;
    }
    private AccessibilityNodeInfo find(AccessibilityNodeInfo node,String text,boolean description){
        if(node==null)return null;
        if(text.contentEquals(node.getContentDescription()==null?"":node.getContentDescription())||(!description&&text.contentEquals(node.getText()==null?"":node.getText())))return node;
        for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo found=find(node.getChild(i),text,description);if(found!=null)return found;}return null;
    }
    private AccessibilityNodeInfo control(String text,boolean description)throws Exception{
        AtomicReference<AccessibilityNodeInfo> found=new AtomicReference<>();waitFor(()->{found.set(find(instrument.getUiAutomation().getRootInActiveWindow(),text,description));return found.get()!=null;});return found.get();
    }
    private void click(String text)throws Exception{
        if("PDF 裁边".equals(text)&&find(instrument.getUiAutomation().getRootInActiveWindow(),text,false)==null){
            android.view.View page=(android.view.View)field(activity,"pdfView");int[] xy=new int[2];instrument.runOnMainSync(()->page.getLocationOnScreen(xy));
            long down=SystemClock.uptimeMillis();pointer(down,MotionEvent.ACTION_DOWN,xy[0]+page.getWidth()*.45f,xy[1]+page.getHeight()/2f);pointer(down,MotionEvent.ACTION_UP,xy[0]+page.getWidth()*.45f,xy[1]+page.getHeight()/2f);Thread.sleep(android.view.ViewConfiguration.getDoubleTapTimeout()+80);
        }
        AccessibilityNodeInfo target=control(text,false);while(!target.isClickable()&&target.getParent()!=null)target=target.getParent();assertTrue(target.performAction(AccessibilityNodeInfo.ACTION_CLICK));instrument.waitForIdleSync();Thread.sleep(250);
    }
    private void dragProgress(String description,float from,float to)throws Exception{
        android.graphics.Rect bounds=new android.graphics.Rect();control(description,true).getBoundsInScreen(bounds);
        float padding=16*contextDensity(),width=bounds.width()-2*padding,y=bounds.exactCenterY();long down=SystemClock.uptimeMillis();
        pointer(down,MotionEvent.ACTION_DOWN,bounds.left+padding+width*from,y);
        for(int i=1;i<=12;i++){Thread.sleep(16);pointer(down,MotionEvent.ACTION_MOVE,bounds.left+padding+width*(from+(to-from)*i/12f),y);}
        pointer(down,MotionEvent.ACTION_UP,bounds.left+padding+width*to,y);instrument.waitForIdleSync();
    }
    private float contextDensity(){return instrument.getTargetContext().getResources().getDisplayMetrics().density;}
    private android.graphics.Bitmap pageImage(PdfPageView view){AtomicReference<android.graphics.Bitmap> out=new AtomicReference<>();instrument.runOnMainSync(()->{android.graphics.Bitmap image=android.graphics.Bitmap.createBitmap(view.getWidth(),view.getHeight(),android.graphics.Bitmap.Config.ARGB_8888);view.draw(new android.graphics.Canvas(image));out.set(image);});return out.get();}
    private int redPixels(android.graphics.Bitmap bitmap){int count=0;for(int y=0;y<bitmap.getHeight();y+=3)for(int x=0;x<bitmap.getWidth();x+=3){int c=bitmap.getPixel(x,y);if(android.graphics.Color.red(c)>180&&android.graphics.Color.green(c)<80&&android.graphics.Color.blue(c)<80)count++;}bitmap.recycle();return count;}
    private void screenshot(Context context,String name)throws Exception{android.graphics.Bitmap image=instrument.getUiAutomation().takeScreenshot();try(java.io.FileOutputStream out=new java.io.FileOutputStream(new File(context.getExternalFilesDir(null),name))){assertTrue(image.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out));}image.recycle();}
    private void progress(String description,int value)throws Exception{
        Bundle args=new Bundle();args.putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE,value);
        assertTrue(control(description,true).performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.getId(),args));instrument.waitForIdleSync();
    }
    private void pointer(long down,int action,float x,float y){MotionEvent e=MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);instrument.sendPointerSync(e);e.recycle();}
    @Test public void cropCanAdjustCopyResetAndShareAcrossBooksWithoutPersisting()throws Exception{
        assertTrue("Use a disposable emulator",android.os.Build.HARDWARE.contains("ranchu")||android.os.Build.HARDWARE.contains("goldfish"));
        // Deliberately do not reset the static setting: each new app process must start off at 10/10.
        assertEquals(PdfCropSettings.defaults(),PdfCropSettings.current());
        Context context=instrument.getTargetContext();context.deleteDatabase("xlib.db");context.getSharedPreferences("xlib_reader",0).edit().clear().commit();
        PDFBoxResourceLoader.init(context);LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0));
        try{
            File directory=new File(context.getFilesDir(),"books");directory.mkdirs();File file=new File(directory,"crop-device.pdf");
            try(PDDocument document=new PDDocument()){
                for(int i=0;i<3;i++){PDPage page=new PDPage();document.addPage(page);try(PDPageContentStream out=new PDPageContentStream(document,page)){out.setNonStrokingColor(255,0,0);out.addRect(0,0,40,792);out.fill();out.setNonStrokingColor(0,0,255);out.addRect(572,0,40,792);out.fill();out.setNonStrokingColor(0,0,0);out.beginText();out.setFont(PDType1Font.HELVETICA,20);out.newLineAtOffset(200,700);out.showText("Hello original page "+(i+1));out.endText();}}
                document.save(file);
            }
            Book book=new Book();book.id=992;book.format="pdf";book.title=book.sourceName="crop-device.pdf";book.encoding="UTF-8";book.path=file.getAbsolutePath();book.fileSize=file.length();
            assertTrue(db.saveBooks(List.of(book),null,0,0));String hash=new BookHashCache(db).resolve(book.id,file).bookHash;
            DocumentLocator original=DocumentLocator.pdf(1,3,0);db.saveDocumentPosition(book,original,hash,1234);assertTrue(db.addDocumentBookmark(book.id,original));byte[] bytes=Files.readAllBytes(file.toPath());
            launch(context,book);PdfPageView view=(PdfPageView)field(activity,"pdfView");Object source=field(view,"page");
            int width=view.getWidth(),height=view.getHeight(),before=redPixels(pageImage(view));assertTrue(before>0);screenshot(context,"pdf-reader-clean.png");
            int[] menuOrigin=new int[2];instrument.runOnMainSync(()->view.getLocationOnScreen(menuOrigin));long menuTap=SystemClock.uptimeMillis();
            pointer(menuTap,MotionEvent.ACTION_DOWN,menuOrigin[0]+width*.45f,menuOrigin[1]+height*.5f);pointer(menuTap,MotionEvent.ACTION_UP,menuOrigin[0]+width*.45f,menuOrigin[1]+height*.5f);Thread.sleep(android.view.ViewConfiguration.getDoubleTapTimeout()+80);
            assertTrue((boolean)field(activity,"readerMenusOpen"));assertEquals(height,view.getHeight());screenshot(context,"pdf-reader-menu.png");
            click("PDF 裁边");assertFalse(control("启用裁边",false).isChecked());assertTrue(control("左侧裁边百分比",true).isEnabled());
            dragProgress("左侧裁边百分比",1/3f,.8f);assertTrue(PdfCropSettings.current().enabled);assertTrue(PdfCropSettings.current().leftPercent>=20);
            dragProgress("右侧裁边百分比",1/3f,.65f);assertTrue(PdfCropSettings.current().rightPercent>=16);
            assertEquals(0,redPixels(pageImage(view)));assertEquals(width,view.getWidth());assertEquals(height,view.getHeight());screenshot(context,"pdf-crop-preview.png");
            progress("左侧裁边百分比",30);progress("右侧裁边百分比",0);
            assertEquals(new PdfCropSettings(true,30,0),PdfCropSettings.current());
            // Default 10/10 leaves this fixture's complete text visible for native long-press dragging.
            progress("左侧裁边百分比",10);progress("右侧裁边百分比",10);click("完成");assertSame(source,field(view,"page"));
            assertEquals(0,redPixels(pageImage(view)));screenshot(context,"pdf-reader-cropped.png");
            int[] origin=new int[2];instrument.runOnMainSync(()->view.getLocationOnScreen(origin));
            long tap=SystemClock.uptimeMillis();pointer(tap,MotionEvent.ACTION_DOWN,origin[0]+view.getWidth()/2f,origin[1]+view.getHeight()/2f);pointer(tap,MotionEvent.ACTION_UP,origin[0]+view.getWidth()/2f,origin[1]+view.getHeight()/2f);
            Thread.sleep(80);tap=SystemClock.uptimeMillis();pointer(tap,MotionEvent.ACTION_DOWN,origin[0]+view.getWidth()/2f,origin[1]+view.getHeight()/2f);pointer(tap,MotionEvent.ACTION_UP,origin[0]+view.getWidth()/2f,origin[1]+view.getHeight()/2f);instrument.waitForIdleSync();
            assertEquals(2f,(float)field(view,"zoom"),.01f);
            java.lang.reflect.Method geometry=PdfPageView.class.getDeclaredMethod("box",int.class);geometry.setAccessible(true);
            AtomicReference<RectF> first=new AtomicReference<>(),last=new AtomicReference<>();int[] screen=new int[2];
            instrument.runOnMainSync(()->{try{view.getLocationOnScreen(screen);first.set((RectF)geometry.invoke(view,1));last.set((RectF)geometry.invoke(view,15));}catch(Exception e){throw new AssertionError(e);}});
            long down=SystemClock.uptimeMillis();pointer(down,MotionEvent.ACTION_DOWN,screen[0]+first.get().centerX(),screen[1]+first.get().centerY());
            Thread.sleep(android.view.ViewConfiguration.getLongPressTimeout()+150);waitFor(view::hasSelection);assertEquals("Hello",view.selectedText());
            assertEquals(width,view.getWidth());assertEquals(height,view.getHeight());
            // Selection reveals a floating copy toolbar; the viewport and glyph transform stay fixed.
            instrument.runOnMainSync(()->{try{view.getLocationOnScreen(screen);last.set((RectF)geometry.invoke(view,15));}catch(Exception e){throw new AssertionError(e);}});
            pointer(down,MotionEvent.ACTION_MOVE,screen[0]+last.get().centerX(),screen[1]+last.get().centerY());pointer(down,MotionEvent.ACTION_UP,screen[0]+last.get().centerX(),screen[1]+last.get().centerY());
            instrument.waitForIdleSync();assertTrue("Selected: "+view.selectedText()+"; target "+last.get()+"; viewport "+view.getWidth()+"x"+view.getHeight(),view.selectedText().startsWith("Hello original"));String selected=view.selectedText();click("复制");AtomicReference<String> clipboard=new AtomicReference<>();
            instrument.runOnMainSync(()->clipboard.set(((ClipboardManager)context.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString()));assertEquals(selected,clipboard.get());
            assertEquals(original,db.loadBooks().get(0).locator);assertEquals(1234,db.loadBooks().get(0).updatedAt);assertEquals(1,db.documentBookmarks(book.id).size());assertArrayEquals(bytes,Files.readAllBytes(file.toPath()));
            assertEquals(hash,new BookHashCache(db).resolve(book.id,file).bookHash);finish();launch(context,book);
            assertEquals(new PdfCropSettings(true,10,10),field(field(activity,"pdfView"),"crop"));
            click("PDF 裁边");click("恢复原页");assertFalse(control("启用裁边",false).isChecked());assertEquals(PdfCropSettings.defaults(),PdfCropSettings.current());
            click("启用裁边");progress("左侧裁边百分比",30);progress("右侧裁边百分比",0);click("完成");finish();
            Book other=new Book();other.id=993;other.format="pdf";other.title=other.sourceName="crop-other.pdf";other.encoding="UTF-8";
            File second=new File(directory,"crop-other.pdf");Files.write(second.toPath(),bytes);other.path=second.getAbsolutePath();other.fileSize=second.length();assertTrue(db.saveBooks(List.of(db.loadBooks().get(0),other),null,0,0));
            launch(context,other);assertEquals(new PdfCropSettings(true,30,0),field(field(activity,"pdfView"),"crop"));
            assertEquals(0,db.loadBooks().stream().filter(b->b.id==other.id).findFirst().get().updatedAt);
            PdfPageView otherView=(PdfPageView)field(activity,"pdfView");Object otherPage=field(otherView,"page");int[] themeOrigin=new int[2];instrument.runOnMainSync(()->otherView.getLocationOnScreen(themeOrigin));long themeTap=SystemClock.uptimeMillis();
            pointer(themeTap,MotionEvent.ACTION_DOWN,themeOrigin[0]+otherView.getWidth()*.45f,themeOrigin[1]+otherView.getHeight()*.5f);pointer(themeTap,MotionEvent.ACTION_UP,themeOrigin[0]+otherView.getWidth()*.45f,themeOrigin[1]+otherView.getHeight()*.5f);Thread.sleep(android.view.ViewConfiguration.getDoubleTapTimeout()+80);
            click("切换阅读主题");assertTrue((boolean)field(activity,"dark"));assertSame(otherPage,field(otherView,"page"));screenshot(context,"pdf-reader-dark-menu.png");
            click("PDF 裁边");screenshot(context,"pdf-crop-dark-preview.png");click("完成");
            // Keep enabled when the process exits; the next instrumentation run must still start disabled.
            assertEquals(new PdfCropSettings(true,30,0),PdfCropSettings.current());
        }finally{finish();db.close();}
    }
}
