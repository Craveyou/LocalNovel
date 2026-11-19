package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.ImageButton;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Disposable emulator checks for custom library/settings surfaces and their dialog controls. */
@RunWith(AndroidJUnit4.class)
public class ModernUiDeviceTest {
    private final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    private final Context context=instrument.getTargetContext();
    private MainActivity activity;
    private Book book;
    private AccessibilityNodeInfo find(AccessibilityNodeInfo node,String label){if(node==null)return null;if(label.contentEquals(node.getText()==null?"":node.getText())||label.contentEquals(node.getContentDescription()==null?"":node.getContentDescription()))return node;for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo child=find(node.getChild(i),label);if(child!=null)return child;}return null;}
    private void click(String label)throws Exception{long end=SystemClock.uptimeMillis()+8000;while(SystemClock.uptimeMillis()<end){AccessibilityNodeInfo node=find(instrument.getUiAutomation().getRootInActiveWindow(),label);if(node!=null){while(node!=null&&!node.isClickable())node=node.getParent();if(node!=null&&node.performAction(AccessibilityNodeInfo.ACTION_CLICK)){instrument.waitForIdleSync();return;}}Thread.sleep(60);}fail("Missing action: "+label);}
    private void invoke(String name,Class<?>[] types,Object...args){instrument.runOnMainSync(()->{try{Method method=MainActivity.class.getDeclaredMethod(name,types);method.setAccessible(true);method.invoke(activity,args);}catch(Exception error){throw new AssertionError(error);}});instrument.waitForIdleSync();}
    private void screenshot(String name)throws Exception{Thread.sleep(450);Bitmap image=instrument.getUiAutomation().takeScreenshot();try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),name))){assertTrue(image.compress(Bitmap.CompressFormat.PNG,100,out));}image.recycle();}
    private void launch()throws Exception{
        assertTrue(android.os.Build.MODEL.contains("sdk")||android.os.Build.FINGERPRINT.contains("generic"));
        File directory=new File(context.getFilesDir(),"books");directory.mkdirs();File source=new File(directory,"modern-ui.txt");try(FileOutputStream out=new FileOutputStream(source)){out.write("界面检查用书籍。\n".repeat(200).getBytes(StandardCharsets.UTF_8));}
        book=new Book();book.id=999020;book.format="txt";book.title="界面检查用书籍";book.sourceName="modern-ui.txt";book.path=source.getAbsolutePath();book.fileSize=source.length();book.encoding="UTF-8";
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertTrue(db.saveBooks(Arrays.asList(book),null,0,0));new ReadingPreferences(db).setAppTheme(ReaderSettingsOptions.THEME_LIGHT);}
        activity=(MainActivity)instrument.startActivitySync(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        long end=SystemClock.uptimeMillis()+15000;while(find(instrument.getUiAutomation().getRootInActiveWindow(),"常规设置")==null&&SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();Thread.sleep(50);}assertNotNull(find(instrument.getUiAutomation().getRootInActiveWindow(),"常规设置"));
    }
    @After public void close()throws Exception{if(activity!=null){
        instrument.runOnMainSync(()->activity.finish());
        // finish() returns before onDestroy closes SQLite. The next test may
        // delete its disposable database only after the old owner is gone.
        long end=SystemClock.uptimeMillis()+10000;
        while(!activity.isDestroyed()&&SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();Thread.sleep(40);}
        assertTrue("Previous activity must release its database",activity.isDestroyed());
        instrument.waitForIdleSync();
    }}
    @Test public void librarySettingsAndCustomDialogsShareThemeAndReachableActions()throws Exception{
        launch();screenshot("modern-library-light.png");
        invoke("showEditBookDialog",new Class<?>[]{Book.class},book);screenshot("modern-edit-light.png");click("取消");
        invoke("showDeleteBookDialog",new Class<?>[]{Book.class},book);screenshot("modern-delete-light.png");click("取消");
        click("常规设置");screenshot("modern-settings-general.png");click("阅读");screenshot("modern-settings-reading.png");click("同步");screenshot("modern-settings-sync.png");
        invoke("showSyncDevices",new Class<?>[]{String.class},"测试设备");screenshot("modern-devices-light.png");click("关闭");
        invoke("setAppTheme",new Class<?>[]{int.class},ReaderSettingsOptions.THEME_DARK);invoke("showLibrary",new Class<?>[]{});screenshot("modern-library-dark.png");
        invoke("showEditBookDialog",new Class<?>[]{Book.class},book);screenshot("modern-edit-dark.png");click("取消");
        invoke("showDeleteBookDialog",new Class<?>[]{Book.class},book);screenshot("modern-delete-dark.png");click("取消");
    }
    @Test public void txtToolbarsKeepAllIconsInsideSurfaceWith48DpTargets()throws Exception{
        launch();invoke("openBook",new Class<?>[]{Book.class},book);
        // Reading may prepare its layout asynchronously before menus can be revealed.
        long end=SystemClock.uptimeMillis()+15000;View[] top={null};
        while(top[0]==null&&SystemClock.uptimeMillis()<end){instrument.runOnMainSync(()->{try{java.lang.reflect.Field field=MainActivity.class.getDeclaredField("readerTopBar");field.setAccessible(true);top[0]=(View)field.get(activity);}catch(Exception error){throw new AssertionError(error);}});Thread.sleep(40);}
        assertNotNull(top[0]);invoke("showReaderMenus",new Class<?>[]{});screenshot("modern-txt-toolbar.png");
        instrument.runOnMainSync(()->assertIcons(top[0]));
    }
    @Test public void realImportDuplicateSwipeEditAndLongPressDeleteCompleteLibraryFlow()throws Exception{
        launch();File input=new File(context.getCacheDir(),"书架流程.txt");try(FileOutputStream out=new FileOutputStream(input)){out.write("独立书架流程：导入、去重、改名和删除。\n".repeat(200).getBytes(StandardCharsets.UTF_8));}
        try{
            invoke("addBooksFromUris",new Class<?>[]{java.util.List.class},java.util.Collections.singletonList(android.net.Uri.fromFile(input)));
            waitLibrary(2);Book imported=null;for(Book b:libraryBooks())if(b.id!=book.id)imported=b;assertNotNull(imported);final Book selected=imported;
            byte[] original=java.nio.file.Files.readAllBytes(input.toPath());File copy=new File(imported.path);assertArrayEquals(original,java.nio.file.Files.readAllBytes(copy.toPath()));
            invoke("addBooksFromUris",new Class<?>[]{java.util.List.class},java.util.Collections.singletonList(android.net.Uri.fromFile(input)));waitLibrary(2);assertEquals(2,libraryBooks().size());
            View row=bookRow("书架流程.txt");gesture(row,false);Thread.sleep(400);assertTrue("Left swipe must remain open",row.getTranslationX()<=-UiKit.dp(context,120));Thread.sleep(450);assertTrue(row.getTranslationX()<=-UiKit.dp(context,120));
            click("编辑书籍信息");setAccessibleText("书名","书架改名");setAccessibleText("作者","流程作者");click("保存");
            long end=SystemClock.uptimeMillis()+8000;while(!"书架改名".equals(selected.title)&&SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();Thread.sleep(50);}assertEquals("书架改名",selected.title);assertEquals("流程作者",selected.author);Thread.sleep(400);
            row=bookRow("书架改名");gesture(row,true);click("删除书籍");click("取消");assertEquals(2,libraryBooks().size());assertTrue(copy.isFile());
            try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertTrue(db.addBookmark(imported.id,10));}
            click("删除书籍");click("删除");waitLibrary(1);assertFalse(copy.exists());assertArrayEquals(original,java.nio.file.Files.readAllBytes(input.toPath()));
            try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertEquals(1,db.loadBooks().size());assertTrue(db.loadBookmarks(imported.id).isEmpty());}
        }finally{input.delete();}
    }
    @SuppressWarnings("unchecked") private java.util.List<Book> libraryBooks()throws Exception{java.lang.reflect.Field f=MainActivity.class.getDeclaredField("books");f.setAccessible(true);return (java.util.List<Book>)f.get(activity);}
    private void waitLibrary(int count)throws Exception{java.lang.reflect.Field f=MainActivity.class.getDeclaredField("imports");f.setAccessible(true);long end=SystemClock.uptimeMillis()+15000;while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();if(libraryBooks().size()==count&&((BookImportController<?>)f.get(activity)).pending().isEmpty())return;Thread.sleep(50);}fail("Library import/delete did not finish");}
    private View textView(View view,String text){if(view instanceof android.widget.TextView&&text.contentEquals(((android.widget.TextView)view).getText()))return view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View hit=textView(((ViewGroup)view).getChildAt(i),text);if(hit!=null)return hit;}return null;}
    private View bookRow(String title)throws Exception{View[] row={null};long end=SystemClock.uptimeMillis()+8000;while(row[0]==null&&SystemClock.uptimeMillis()<end){instrument.runOnMainSync(()->{View label=textView(activity.getWindow().getDecorView(),title);if(label!=null)row[0]=(View)label.getParent().getParent();});Thread.sleep(50);}assertNotNull(title,row[0]);return row[0];}
    private void setAccessibleText(String label,String value)throws Exception{long end=SystemClock.uptimeMillis()+8000;while(SystemClock.uptimeMillis()<end){AccessibilityNodeInfo input=find(instrument.getUiAutomation().getRootInActiveWindow(),label);if(input!=null){android.os.Bundle args=new android.os.Bundle();args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,value);if(input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,args))return;}Thread.sleep(50);}fail("Missing input: "+label);}
    private void gesture(View row,boolean longPress)throws Exception{int[] origin=new int[2];instrument.runOnMainSync(()->row.getLocationOnScreen(origin));float x=origin[0]+row.getWidth()*.75f,y=origin[1]+row.getHeight()*.5f;long down=SystemClock.uptimeMillis();pointer(down,0,x,y);if(longPress)Thread.sleep(android.view.ViewConfiguration.getLongPressTimeout()+150);else for(int i=1;i<=16;i++){Thread.sleep(16);pointer(down,2,x-UiKit.dp(context,160)*i/16f,y+UiKit.dp(context,2)*i/16f);}pointer(down,1,longPress?x:x-UiKit.dp(context,160),y);instrument.waitForIdleSync();}
    private void pointer(long down,int action,float x,float y){android.view.MotionEvent event=android.view.MotionEvent.obtain(down,SystemClock.uptimeMillis(),action,x,y,0);instrument.sendPointerSync(event);event.recycle();}
    private void assertIcons(View view){if(view instanceof ImageButton&&view.getVisibility()==View.VISIBLE){assertTrue(view.getWidth()>=UiKit.dp(context,48));assertTrue(view.getHeight()>=UiKit.dp(context,48));assertNotNull(view.getContentDescription());View parent=(View)view.getParent();assertTrue(view.getLeft()>=0&&view.getRight()<=parent.getWidth());}if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)assertIcons(((ViewGroup)view).getChildAt(i));}
}
