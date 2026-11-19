package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.shadows.ShadowAlertDialog;
import java.io.File;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.function.BooleanSupplier;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class PdfReaderFlowTest {
    private Context context;
    private LocalDatabase database;
    private ActivityController<DocumentReaderActivity> controller;
    @Before public void setup() throws Exception {
        PdfCropSettings.reset();
        context = RuntimeEnvironment.getApplication(); context.deleteDatabase("xlib.db");
        context.getSharedPreferences("xlib_reader", 0).edit().clear().commit();
        database = LocalDatabase.open(context, context.getSharedPreferences("xlib_reader", 0));
    }
    @After public void teardown() throws Exception {
        if (controller != null) controller.pause().stop().destroy();
        database.close();
        PdfCropSettings.reset();
    }
    private Book book(String password) throws Exception {
        File directory = new File(context.getFilesDir(), "books"); directory.mkdirs();
        File target = new File(directory, "flow.pdf");
        Files.copy(PdfDocumentTest.fixture(context, "flow-source.pdf", password, true, true).toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING);
        Book b = new Book(); b.id = 88001; b.format = "pdf"; b.title = b.sourceName = "flow.pdf";
        b.path = target.getAbsolutePath(); b.fileSize = target.length(); b.encoding = "UTF-8";
        assertTrue(database.saveBooks(List.of(b), null, 0, 0)); return b;
    }
    private DocumentReaderActivity launch(Book b) {
        controller = Robolectric.buildActivity(DocumentReaderActivity.class,
                new Intent(context, DocumentReaderActivity.class).putExtra("bookId", b.id)).setup(); return controller.get();
    }
    private static Object field(Object o, String name) {
        try { Field f = o.getClass().getDeclaredField(name); f.setAccessible(true); return f.get(o); }
        catch (Exception e) { throw new AssertionError(e); }
    }
    private static void call(Object object,String name,Class<?>[] signature,Object...arguments) {
        try {java.lang.reflect.Method method=object.getClass().getDeclaredMethod(name,signature);method.setAccessible(true);method.invoke(object,arguments);}
        catch(Exception failure){throw new AssertionError(failure);}
    }
    private static void waitFor(BooleanSupplier condition) throws Exception {
        long end = System.nanoTime() + 15_000_000_000L;
        while (!condition.getAsBoolean() && System.nanoTime() < end) { Shadows.shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(10); }
        Shadows.shadowOf(Looper.getMainLooper()).idle(); assertTrue("Asynchronous reader operation timed out", condition.getAsBoolean());
    }
    private static View button(View root, String text) {
        if (root instanceof Button && text.contentEquals(((Button) root).getText())) return root;
        if(text.contentEquals(root.getContentDescription()==null?"":root.getContentDescription()))return root;
        if (root instanceof ViewGroup) for (int i = 0; i < ((ViewGroup) root).getChildCount(); i++) {
            View b = button(((ViewGroup) root).getChildAt(i), text); if (b != null) return b;
        }
        return null;
    }
    private void replacePdf(Book book, boolean text) throws Exception {
        Files.copy(PdfDocumentTest.fixture(context,"capability.pdf",null,true,text).toPath(),new File(book.path).toPath(),StandardCopyOption.REPLACE_EXISTING);
    }
    private static void assertNoCapabilityNotice(View root) {
        if(root instanceof android.widget.TextView){String text=((android.widget.TextView)root).getText().toString();assertFalse(text.contains("可靠文本"));assertFalse(text.contains("同步位置"));}
        if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++)assertNoCapabilityNotice(((ViewGroup)root).getChildAt(i));
    }
    @Test public void imageOnlyPdfDisablesTextActionsWithoutOverlayAndKeepsBookmarks() throws Exception {
        Book b=book(null);replacePdf(b,false);DocumentReaderActivity activity=launch(b);
        waitFor(()->field(field(activity,"pdfView"),"page")!=null);
        waitFor(()->(int)field(activity,"nextTextProbe")==3&&!(boolean)field(activity,"textProbePending"));
        View root=activity.getWindow().getDecorView(),search=button(root,"搜索");
        assertFalse(search.isEnabled());assertEquals(.35f,search.getAlpha(),0f);assertFalse(((View)field(activity,"copy")).isEnabled());
        call(activity,"setReaderMenus",new Class<?>[]{boolean.class},true);
        assertNoCapabilityNotice(root);assertTrue(button(root,"书签").isEnabled());
        call(activity,"showSearch",new Class<?>[]{});assertNull(ShadowAlertDialog.getLatestAlertDialog());
        button(root,"下一页").performClick();waitFor(()->((DocumentLocator)field(activity,"position")).page==1);
        button(root,"上一页").performClick();waitFor(()->((DocumentLocator)field(activity,"position")).page==0);
        assertFalse(search.isEnabled());assertFalse(((View)field(activity,"copy")).isEnabled());
    }
    @Test public void blankCoverDoesNotDisableWholeBookSearchAndBlankPageCannotCopy() throws Exception {
        Book b=book(null);
        try(com.tom_roush.pdfbox.pdmodel.PDDocument doc=com.tom_roush.pdfbox.pdmodel.PDDocument.load(new File(b.path))){
            doc.getPage(0).setContents(new com.tom_roush.pdfbox.pdmodel.common.PDStream(doc));
            File edited=new File(context.getCacheDir(),"mixed.pdf");doc.save(edited);Files.copy(edited.toPath(),new File(b.path).toPath(),StandardCopyOption.REPLACE_EXISTING);
        }
        DocumentReaderActivity activity=launch(b);View root=activity.getWindow().getDecorView();
        waitFor(()->button(root,"搜索").isEnabled());assertFalse(((View)field(activity,"copy")).isEnabled());
        button(root,"下一页").performClick();waitFor(()->((DocumentLocator)field(activity,"position")).page==1);
        assertTrue(((View)field(activity,"copy")).isEnabled());
        button(root,"上一页").performClick();waitFor(()->((DocumentLocator)field(activity,"position")).page==0);
        assertTrue(button(root,"搜索").isEnabled());assertFalse(((View)field(activity,"copy")).isEnabled());assertNoCapabilityNotice(root);
    }
    @Test public void extractionRestrictedPdfDisablesTextActionsWithoutExplanationPopup() throws Exception {
        Book b=book(null);Files.copy(PdfDocumentTest.fixture(context,"restricted-capability.pdf","",false,true).toPath(),new File(b.path).toPath(),StandardCopyOption.REPLACE_EXISTING);
        DocumentReaderActivity activity=launch(b);waitFor(()->field(field(activity,"pdfView"),"page")!=null);
        View root=activity.getWindow().getDecorView();assertFalse(button(root,"搜索").isEnabled());assertFalse(((View)field(activity,"copy")).isEnabled());
        call(activity,"setReaderMenus",new Class<?>[]{boolean.class},true);assertNoCapabilityNotice(root);assertTrue(button(root,"书签").isEnabled());
    }
    @Test public void imageOnlyEpubDisablesSearchAndCopyWithoutCapabilityNotice() throws Exception {
        File source=new EpubDocumentTest().sample(null,"");File directory=new File(context.getFilesDir(),"books");directory.mkdirs();File target=new File(directory,"images.epub");
        try(java.util.zip.ZipFile zip=new java.util.zip.ZipFile(source);java.util.zip.ZipOutputStream out=new java.util.zip.ZipOutputStream(new java.io.FileOutputStream(target))){
            java.util.Enumeration<? extends java.util.zip.ZipEntry> entries=zip.entries();
            while(entries.hasMoreElements()){
                java.util.zip.ZipEntry entry=entries.nextElement();out.putNextEntry(new java.util.zip.ZipEntry(entry.getName()));
                if(entry.getName().endsWith("z.xhtml")||entry.getName().endsWith("a.xhtml"))out.write("<html xmlns='http://www.w3.org/1999/xhtml'><body><img src='page.png'/></body></html>".getBytes(java.nio.charset.StandardCharsets.UTF_8));
                else try(java.io.InputStream in=zip.getInputStream(entry)){byte[] buf=new byte[4096];int n;while((n=in.read(buf))!=-1)out.write(buf,0,n);}
                out.closeEntry();
            }
            out.putNextEntry(new java.util.zip.ZipEntry("OPS/page.png"));out.write(java.util.Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a9sAAAAASUVORK5CYII="));out.closeEntry();
        }
        Book b=new Book();b.id=88002;b.format="epub";b.title=b.sourceName="images.epub";b.path=target.getAbsolutePath();b.fileSize=target.length();b.encoding="UTF-8";assertTrue(database.saveBooks(List.of(b),null,0,0));
        DocumentReaderActivity activity=launch(b);waitFor(()->field(activity,"epubView")!=null);
        View root=activity.getWindow().getDecorView();assertFalse(button(root,"搜索").isEnabled());assertFalse(((View)field(activity,"copy")).isEnabled());assertTrue(button(root,"书签").isEnabled());assertNoCapabilityNotice(root);
    }
    @Test public void opensOfflineAndCommitsOnlySuccessfulNavigationThenRestoresOnReopen() throws Exception {
        Book b = book(null); final DocumentReaderActivity activity = launch(b);
        waitFor(() -> field(field(activity, "pdfView"), "page") != null);
        assertEquals(0, database.loadBooks().get(0).updatedAt);
        button(activity.getWindow().getDecorView(), "下一页").performClick();
        waitFor(() -> database.loadBooks().get(0).locator.page == 1);
        long time = database.loadBooks().get(0).updatedAt; assertTrue(time > 0);
        controller.pause().stop().destroy(); controller = null;
        final DocumentReaderActivity reopened = launch(database.loadBooks().get(0));
        waitFor(() -> field(field(reopened, "pdfView"), "page") != null);
        assertEquals(1, database.loadBooks().get(0).locator.page); assertEquals(time, database.loadBooks().get(0).updatedAt);
    }
    @Test public void passwordWrongRetryAndCancelCannotGenerateReadingTime() throws Exception {
        Book b = book("reader-test-only"); DocumentReaderActivity activity = launch(b);
        waitFor(() -> ShadowAlertDialog.getLatestAlertDialog() != null && ShadowAlertDialog.getLatestAlertDialog().isShowing());
        assertFalse((boolean) field(activity, "ready")); assertEquals(0, database.loadBooks().get(0).updatedAt);
        AlertDialog dialog = ShadowAlertDialog.getLatestAlertDialog();
        button(activity.getWindow().getDecorView(),"PDF 裁边").performClick();
        assertSame(dialog,ShadowAlertDialog.getLatestAlertDialog());assertEquals(PdfCropSettings.defaults(),PdfCropSettings.current());
        EditText input = findInput(dialog.getWindow().getDecorView()); input.setText("wrong"); dialog.getButton(-1).performClick();
        final AlertDialog previous = dialog;
        waitFor(() -> ShadowAlertDialog.getLatestAlertDialog() != previous && ShadowAlertDialog.getLatestAlertDialog().isShowing());
        dialog = ShadowAlertDialog.getLatestAlertDialog(); findInput(dialog.getWindow().getDecorView()).setText("reader-test-only"); dialog.getButton(-1).performClick();
        waitFor(() -> field(field(activity, "pdfView"), "page") != null);
        assertEquals(0, database.loadBooks().get(0).updatedAt);
    }
    @Test public void openingPageCannotBeInterruptedByReaderActionsBeforeTheRendererAcknowledges() throws Exception {
        Book b=book(null);
        controller=Robolectric.buildActivity(DocumentReaderActivity.class,
                new Intent(context,DocumentReaderActivity.class).putExtra("bookId",b.id));
        DocumentReaderActivity activity=controller.get();
        ExecutorService worker=(ExecutorService)field(activity,"worker");
        CountDownLatch parseGate=new CountDownLatch(1);
        worker.execute(()->{try{parseGate.await();}catch(InterruptedException ignored){Thread.currentThread().interrupt();}});
        controller.setup();
        // Block rendering after parsing, before allowing its UI callback to run.
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        worker.execute(()->{entered.countDown();try{release.await();}catch(InterruptedException ignored){Thread.currentThread().interrupt();}});
        parseGate.countDown();
        assertTrue(entered.await(5,TimeUnit.SECONDS));
        try {
            Shadows.shadowOf(Looper.getMainLooper()).idle();
            assertTrue((boolean)field(activity,"opening"));
            button(activity.getWindow().getDecorView(),"下一页").performClick();
            button(activity.getWindow().getDecorView(),"搜索").performClick();
            button(activity.getWindow().getDecorView(),"书签").performClick();
            assertNull(field(activity,"search"));assertNull(field(activity,"sync"));
            assertEquals(0,database.loadBooks().get(0).updatedAt);
        } finally { release.countDown(); }
        waitFor(()->field(activity,"sync")!=null);
        assertEquals(0,((DocumentLocator)field(activity,"position")).page);
        assertEquals(0,database.loadBooks().get(0).updatedAt);
    }
    @Test public void cancellingAndReplacingQueuedSearchCannotDisplayStaleResultsOrErrors() throws Exception {
        DocumentReaderActivity activity=launch(book(null));waitFor(()->field(activity,"sync")!=null);
        ExecutorService worker=(ExecutorService)field(activity,"worker");
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        worker.execute(()->{entered.countDown();try{release.await();}catch(InterruptedException ignored){Thread.currentThread().interrupt();}});
        assertTrue(entered.await(5,TimeUnit.SECONDS));
        try {
            call(activity,"beginSearch",new Class<?>[]{String.class,boolean.class},"Hello",true);
            assertTrue((boolean)field(activity,"searching"));
            AlertDialog loading=ShadowAlertDialog.getLatestAlertDialog();
            assertEquals("正在搜索文档…",Shadows.shadowOf(loading).getTitle());
            loading.getButton(AlertDialog.BUTTON_NEGATIVE).performClick();
            Shadows.shadowOf(Looper.getMainLooper()).idle();
            assertFalse((boolean)field(activity,"searching"));assertNull(field(activity,"search"));assertFalse(loading.isShowing());
            call(activity,"beginSearch",new Class<?>[]{String.class,boolean.class},"page 3",true);
        }finally{release.countDown();}
        waitFor(()->!(boolean)field(activity,"searching"));
        List<DocumentSearch.Hit> hits=(List<DocumentSearch.Hit>)field(activity,"searchHits");
        assertEquals(1,hits.size());assertEquals(2,hits.get(0).locator.page);
        assertTrue(ShadowAlertDialog.getLatestAlertDialog().isShowing());
        assertEquals(0,database.loadBooks().get(0).updatedAt);
    }
    @Test public void backgroundCancelsQueuedSearchAndDisablesKeepAwakeWithoutSavingProgress() throws Exception {
        new ReadingPreferences(database).setReadingKeepScreenOn(true);
        DocumentReaderActivity activity=launch(book(null));waitFor(()->field(activity,"sync")!=null);
        int keepAwake=android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON;
        assertNotEquals(0,activity.getWindow().getAttributes().flags&keepAwake);
        ExecutorService worker=(ExecutorService)field(activity,"worker");
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        worker.execute(()->{entered.countDown();try{release.await();}catch(InterruptedException ignored){Thread.currentThread().interrupt();}});
        assertTrue(entered.await(5,TimeUnit.SECONDS));
        try {
            call(activity,"beginSearch",new Class<?>[]{String.class,boolean.class},"Hello",true);
            controller.pause();
            assertEquals(0,activity.getWindow().getAttributes().flags&keepAwake);
            assertNull(field(activity,"search"));assertFalse(ShadowAlertDialog.getLatestAlertDialog().isShowing());
        }finally{release.countDown();}
        worker.submit(()->{}).get(5,TimeUnit.SECONDS);Shadows.shadowOf(Looper.getMainLooper()).idle();
        assertFalse(ShadowAlertDialog.getLatestAlertDialog().isShowing());
        controller.resume();assertNotEquals(0,activity.getWindow().getAttributes().flags&keepAwake);
        assertEquals(0,database.loadBooks().get(0).updatedAt);
    }
    @Test public void wholeBookSearchPreviewAndReturnPreserveTheFormalPageAndTime() throws Exception {
        DocumentReaderActivity activity=launch(book(null));waitFor(()->field(activity,"sync")!=null);
        button(activity.getWindow().getDecorView(),"下一页").performClick();
        waitFor(()->database.loadBooks().get(0).locator.page==1);
        long time=database.loadBooks().get(0).updatedAt;
        call(activity,"beginSearch",new Class<?>[]{String.class,boolean.class},"Hello",true);
        waitFor(()->!(boolean)field(activity,"searching"));
        List<DocumentSearch.Hit> hits=(List<DocumentSearch.Hit>)field(activity,"searchHits");
        assertEquals(3,hits.size());assertTrue(((DocumentSearch)field(activity,"search")).complete);
        Shadows.shadowOf(ShadowAlertDialog.getLatestAlertDialog()).clickOnItem(0);
        waitFor(()->((DocumentLocator)field(activity,"position")).page==0);
        assertTrue((boolean)field(activity,"temporary"));
        button(activity.getWindow().getDecorView(),"PDF 裁边").performClick();
        PdfCropControls crop=(PdfCropControls)findCrop(ShadowAlertDialog.getLatestAlertDialog().getWindow().getDecorView());
        ((android.widget.CheckBox)field(crop,"enabled")).setChecked(true);
        ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        Shadows.shadowOf(Looper.getMainLooper()).idle();
        assertEquals(1,database.loadBooks().get(0).locator.page);assertEquals(time,database.loadBooks().get(0).updatedAt);
        // The first back cancels the native selection; the next returns to formal reading.
        activity.onBackPressed();if((boolean)field(activity,"temporary"))activity.onBackPressed();
        waitFor(()->((DocumentLocator)field(activity,"position")).page==1);
        assertEquals(time,database.loadBooks().get(0).updatedAt);
    }

    private static View findCrop(View root){
        if(root instanceof PdfCropControls)return root;
        if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){View value=findCrop(((ViewGroup)root).getChildAt(i));if(value!=null)return value;}
        return null;
    }
    @Test public void pdfUsesCurrentReaderChromeAndFloatingMenusDoNotResizeThePage()throws Exception{
        DocumentReaderActivity activity=launch(book(null));waitFor(()->field(activity,"sync")!=null);
        assertTrue(field(activity,"readerChrome") instanceof ReaderChrome);
        PdfPageView view=(PdfPageView)field(activity,"pdfView");View top=(View)field(activity,"readerTopBar"),bottom=(View)field(activity,"readerBottomBar");
        assertEquals(View.GONE,top.getVisibility());assertEquals(View.GONE,bottom.getVisibility());int width=view.getWidth(),height=view.getHeight();
        long now=android.os.SystemClock.uptimeMillis();
        for(int action:new int[]{android.view.MotionEvent.ACTION_DOWN,android.view.MotionEvent.ACTION_UP}){android.view.MotionEvent event=android.view.MotionEvent.obtain(now,now+20,action,width*.45f,height*.5f,0);view.onTouchEvent(event);event.recycle();}
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(400));
        assertEquals(View.VISIBLE,top.getVisibility());assertEquals(View.VISIBLE,bottom.getVisibility());assertEquals(width,view.getWidth());assertEquals(height,view.getHeight());
        activity.onBackPressed();assertFalse(activity.isFinishing());assertEquals(View.GONE,top.getVisibility());assertEquals(0,database.loadBooks().get(0).updatedAt);
    }
    @Test public void returningToCachedPdfPageDoesNotWaitForTheWorkerAndTrimReleasesOnlyOffscreenPages()throws Exception{
        DocumentReaderActivity activity=launch(book(null));waitFor(()->field(activity,"sync")!=null);
        PdfPageView view=(PdfPageView)field(activity,"pdfView");Object first=field(view,"page");
        button(activity.getWindow().getDecorView(),"下一页").performClick();waitFor(()->database.loadBooks().get(0).locator.page==1);
        assertSame(first,view.cachedPage(0));ExecutorService worker=(ExecutorService)field(activity,"worker");CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        worker.execute(()->{entered.countDown();try{release.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}});assertTrue(entered.await(5,TimeUnit.SECONDS));
        try{
            button(activity.getWindow().getDecorView(),"上一页").performClick();assertEquals(0,database.loadBooks().get(0).locator.page);assertSame(first,field(view,"page"));
            activity.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW);assertNull(view.cachedPage(1));assertFalse(((PdfDocument.Page)first).bitmap.isRecycled());
        }finally{release.countDown();}
    }
    @Test public void cropControlsShareAcrossBooksAndReopenWithoutChangingFilePositionTimeOrBookmarks()throws Exception{
        Book b=book(null);DocumentLocator saved=DocumentLocator.pdf(1,3,.2);
        String hash=new BookHashCache(database).resolve(b.id,new File(b.path)).bookHash;
        database.saveDocumentPosition(b,saved,hash,1234);assertTrue(database.addDocumentBookmark(b.id,saved));
        byte[] original=Files.readAllBytes(new File(b.path).toPath());
        DocumentReaderActivity activity=launch(database.loadBooks().get(0));waitFor(()->field(activity,"sync")!=null);
        Object bitmap=field(field(activity,"pdfView"),"page");
        button(activity.getWindow().getDecorView(),"PDF 裁边").performClick();
        AlertDialog panel=ShadowAlertDialog.getLatestAlertDialog();PdfCropControls controls=(PdfCropControls)findCrop(panel.getWindow().getDecorView());assertNotNull(controls);
        android.widget.CheckBox enabled=(android.widget.CheckBox)field(controls,"enabled");
        android.widget.SeekBar left=(android.widget.SeekBar)field(controls,"left"),right=(android.widget.SeekBar)field(controls,"right");
        assertFalse(enabled.isChecked());assertTrue(left.isEnabled());assertEquals(10,left.getProgress());assertEquals(10,right.getProgress());
        enabled.setChecked(true);left.setProgress(30);right.setProgress(0);
        assertEquals(new PdfCropSettings(true,30,0),PdfCropSettings.current());assertEquals(PdfCropSettings.current(),field(field(activity,"pdfView"),"crop"));
        assertSame(bitmap,field(field(activity,"pdfView"),"page"));panel.getButton(AlertDialog.BUTTON_POSITIVE).performClick();Shadows.shadowOf(Looper.getMainLooper()).idle();
        assertEquals(saved,database.loadBooks().get(0).locator);assertEquals(1234,database.loadBooks().get(0).updatedAt);assertEquals(1,database.documentBookmarks(b.id).size());
        assertArrayEquals(original,Files.readAllBytes(new File(b.path).toPath()));assertEquals(hash,new BookHashCache(database).resolve(b.id,new File(b.path)).bookHash);
        controller.pause().stop().destroy();controller=null;
        // Another PDF in the same process inherits the display settings.
        Book other=new Book();other.id=88002;other.format="pdf";other.title=other.sourceName="other.pdf";other.encoding="UTF-8";
        File target=new File(context.getFilesDir(),"books/other.pdf");Files.write(target.toPath(),original);other.path=target.getAbsolutePath();other.fileSize=target.length();
        assertTrue(database.saveBooks(List.of(database.loadBooks().get(0),other),null,0,0));
        DocumentReaderActivity second=launch(other);waitFor(()->field(second,"sync")!=null);
        assertEquals(new PdfCropSettings(true,30,0),field(field(second,"pdfView"),"crop"));
        button(second.getWindow().getDecorView(),"PDF 裁边").performClick();panel=ShadowAlertDialog.getLatestAlertDialog();panel.getButton(AlertDialog.BUTTON_NEUTRAL).performClick();
        Shadows.shadowOf(Looper.getMainLooper()).idle();assertTrue(panel.isShowing());assertEquals(PdfCropSettings.defaults(),PdfCropSettings.current());
        assertEquals(PdfCropSettings.defaults(),field(field(second,"pdfView"),"crop"));panel.dismiss();
        controller.pause().stop().destroy();controller=null;
        DocumentReaderActivity reopened=launch(b);waitFor(()->field(reopened,"sync")!=null);
        assertEquals(saved,field(reopened,"position"));assertEquals(1234,database.loadBooks().stream().filter(book->book.id==b.id).findFirst().get().updatedAt);
    }

    @Test public void failedPdfCanRetryInPlaceAfterFileRecoveryWithoutLosingPositionTimeOrBookmarks() throws Exception {
        Book b=book(null);
        DocumentLocator saved=DocumentLocator.pdf(1,3,0);
        String hash=new BookHashCache(database).resolve(b.id,new File(b.path)).bookHash;
        database.saveDocumentPosition(b,saved,hash,1234);
        assertTrue(database.addDocumentBookmark(b.id,saved));
        File holding=new File(context.getCacheDir(),"recoverable-source.pdf");
        Files.copy(new File(b.path).toPath(),holding.toPath(),StandardCopyOption.REPLACE_EXISTING);
        Files.write(new File(b.path).toPath(),"interrupted PDF source".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        DocumentReaderActivity activity=launch(database.loadBooks().get(0));
        waitFor(()->ShadowAlertDialog.getLatestAlertDialog()!=null&&ShadowAlertDialog.getLatestAlertDialog().isShowing());
        AlertDialog failed=ShadowAlertDialog.getLatestAlertDialog();
        assertEquals("重试打开",failed.getButton(AlertDialog.BUTTON_POSITIVE).getText().toString());
        assertFalse((boolean)field(activity,"ready"));assertNull(field(activity,"sync"));
        // A second failed attempt remains recoverable in the same Activity.
        failed.getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        waitFor(()->ShadowAlertDialog.getLatestAlertDialog()!=failed&&ShadowAlertDialog.getLatestAlertDialog().isShowing());
        assertFalse(activity.isFinishing());
        Files.move(holding.toPath(),new File(b.path).toPath(),StandardCopyOption.REPLACE_EXISTING);
        ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        waitFor(()->field(activity,"sync")!=null);
        assertEquals(saved,field(activity,"position"));assertEquals(1234L,database.loadBooks().get(0).updatedAt);
        assertEquals(saved,database.loadBooks().get(0).locator);
        assertEquals(1,database.documentBookmarks(b.id).size());
    }

    @Test public void failedEncryptedPdfRetryStillRequiresPasswordAndReturnKeepsTheBook() throws Exception {
        Book b=book("reader-test-only");
        File holding=new File(context.getCacheDir(),"recoverable-encrypted.pdf");
        Files.copy(new File(b.path).toPath(),holding.toPath(),StandardCopyOption.REPLACE_EXISTING);
        Files.write(new File(b.path).toPath(),"interrupted encrypted PDF source".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        DocumentReaderActivity activity=launch(b);
        waitFor(()->ShadowAlertDialog.getLatestAlertDialog()!=null&&ShadowAlertDialog.getLatestAlertDialog().isShowing());
        Files.move(holding.toPath(),new File(b.path).toPath(),StandardCopyOption.REPLACE_EXISTING);
        ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick();
        waitFor(()->"此 PDF 需要密码".contentEquals(Shadows.shadowOf(ShadowAlertDialog.getLatestAlertDialog()).getTitle()));
        assertFalse((boolean)field(activity,"ready"));assertNull(field(activity,"sync"));
        ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_NEGATIVE).performClick();
        waitFor(activity::isFinishing);assertEquals(1,database.loadBooks().size());
        assertEquals(0,database.loadBooks().get(0).updatedAt);
    }
    private static EditText findInput(View view) {
        if (view instanceof EditText) return (EditText) view;
        if (view instanceof ViewGroup) for (int i=0;i<((ViewGroup)view).getChildCount();i++) { EditText e=findInput(((ViewGroup)view).getChildAt(i)); if(e!=null)return e; }
        return null;
    }
}
