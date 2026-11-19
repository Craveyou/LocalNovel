package com.xlib.txtreader;

import static org.junit.Assert.*;
import static org.junit.Assume.assumeTrue;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Debug;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.io.FileInputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;

/** Explicit opt-in; exclusively for a disposable emulator. Resets its test application DB. */
@RunWith(AndroidJUnit4.class)
@android.annotation.TargetApi(35)
public class DocumentPerformanceTest {
    private final Instrumentation instrument = InstrumentationRegistry.getInstrumentation();
    private Context context;
    private DocumentReaderActivity activity;
    private static Object field(Object object,String name) {
        try { Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(object); }
        catch(Exception e){throw new AssertionError(e);}
    }
    private static Object call(Object object,String name,Class<?>[] signature,Object...args) {
        try {Method m=object.getClass().getDeclaredMethod(name,signature);m.setAccessible(true);return m.invoke(object,args);}
        catch(Exception e){throw new AssertionError(e);}
    }
    private double now(){return SystemClock.elapsedRealtimeNanos()/1_000_000d;}
    private void waitFor(BooleanSupplier check)throws Exception {
        double deadline=now()+120_000;
        while(now()<deadline){AtomicReference<Boolean> value=new AtomicReference<>();instrument.runOnMainSync(()->value.set(check.getAsBoolean()));if(value.get())return;Thread.sleep(10);}
        throw new AssertionError("Performance flow timed out");
    }
    private void open(Book book)throws Exception {
        activity=(DocumentReaderActivity)instrument.startActivitySync(new Intent(context,DocumentReaderActivity.class).putExtra("bookId",book.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        waitFor(()->field(activity,"sync")!=null);
        // Include the next UI frame after renderer readiness.
        CountDownLatch frame=new CountDownLatch(1);instrument.runOnMainSync(()->activity.getWindow().getDecorView().postOnAnimation(frame::countDown));
        assertTrue(frame.await(5,TimeUnit.SECONDS));
    }
    private void closeReader()throws Exception {
        if(activity==null)return;
        ExecutorService worker=(ExecutorService)field(activity,"worker");
        instrument.runOnMainSync(()->activity.finish());
        assertTrue(worker.awaitTermination(20,TimeUnit.SECONDS));activity=null;
    }
    private void assertVisible(DocumentLocator locator)throws Exception {
        if(!"epub".equals(locator.format))return;
        Thread.sleep(50);
        CountDownLatch result=new CountDownLatch(1);AtomicReference<String> top=new AtomicReference<>();
        String script="(function(){var offset="+locator.textOffset+",sum=0;for(var n of window.xlibNodes){if(sum+n.length>offset){var r=document.createRange();r.setStart(n,offset-sum);r.setEnd(n,Math.min(n.length,offset-sum+1));return r.getBoundingClientRect().top;}sum+=n.length;}return -9999;})()";
        instrument.runOnMainSync(()->((EpubPageView)field(activity,"epubView")).evaluateJavascript(script,value->{top.set(value);result.countDown();}));
        assertTrue(result.await(10,TimeUnit.SECONDS));
        assertEquals("Restored text must actually be visible",16,Double.parseDouble(top.get()),60);
        EpubDocument epub=(EpubDocument)field(activity,"epub");
        int start=epub.chapters.get(locator.spineIndex).text.indexOf("DOCNEEDLE",locator.textOffset);
        if(start>=0){
            instrument.runOnMainSync(()->((EpubPageView)field(activity,"epubView")).highlight(start,9));
            waitFor(()->"DOCNEEDLE".equals(field(activity,"epubSelection")));
            instrument.runOnMainSync(()->((EpubPageView)field(activity,"epubView")).clearSelection());
            waitFor(()->"".equals(field(activity,"epubSelection")));
        }
    }
    private final class Sampler implements AutoCloseable {
        final ScheduledExecutorService sampler=Executors.newSingleThreadScheduledExecutor();
        final Handler main=new Handler(Looper.getMainLooper());
        volatile double peak, gap;double previous=now();volatile boolean stopped;
        final Runnable pulse=new Runnable(){public void run(){if(stopped)return;double t=now();gap=Math.max(gap,t-previous);previous=t;main.postDelayed(this,20);}};
        Sampler(){sampler.scheduleAtFixedRate(()->peak=Math.max(peak,Debug.getPss()/1024d),0,50,TimeUnit.MILLISECONDS);main.post(pulse);}
        public void close(){stopped=true;main.removeCallbacks(pulse);sampler.shutdownNow();}
    }
    @Test public void measureDocuments()throws Exception {
        Bundle args=InstrumentationRegistry.getArguments();
        assumeTrue("Opt-in simulator measurements", "1".equals(args.getString("documentPerformance")));
        assertTrue("Disposable emulator required",android.os.Build.HARDWARE.contains("ranchu")||android.os.Build.HARDWARE.contains("goldfish"));
        context=instrument.getTargetContext();
        String name=args.getString("sample","pdf-small");
        String filename=name+(name.startsWith("epub")?".epub":".pdf");
        int runs=Integer.parseInt(args.getString("runs","3"));assertTrue(runs>=1&&runs<=10);
        context.deleteDatabase("xlib.db");context.getSharedPreferences("xlib_reader",0).edit().clear().commit();
        File source=new File(context.getCacheDir(),filename);
        try(java.io.InputStream input=instrument.getContext().getAssets().open(filename);java.io.FileOutputStream out=new java.io.FileOutputStream(source)){input.transferTo(out);}
        for(int run=0;run<runs;run++) {
            LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0));
            Book[] imported=new Book[1];
            JSONObject result=new JSONObject().put("platform","android-api35-debug").put("sample",name).put("run",run+1).put("source_bytes",source.length());
            Sampler meter=new Sampler();
            try {
                double started=now();
                BookImportController<File> controller=new BookImportController<>(new File(context.getFilesDir(),"books"),new BookImportController.Source<File>(){
                    public String name(File f){return f.getName();}
                    public java.io.InputStream open(File f)throws Exception{return new FileInputStream(f);}
                    public void validate(File f,String format)throws Exception{DocumentFormats.validate(context,f,format);}
                },Runnable::run,Runnable::run,new BookImportController.Listener(){
                    public void changed(){}
                    public void publish(Book b){assertTrue(db.saveBooks(List.of(b),null,0,0));imported[0]=b;}
                    public void finished(int added,int duplicates,int failed){assertEquals(1,added);assertEquals(0,failed);}
                });
                controller.importBooks(List.of(source),List.of());controller.close();
                result.put("import_ms",now()-started);Book book=imported[0];assertNotNull(book);
                started=now();open(book);result.put("open_ms",now()-started);
                DocumentLocator initial=(DocumentLocator)field(activity,"formal");assertEquals(0,book.updatedAt);
                int units=initial.format.equals("pdf")?initial.pageCount:initial.spineCount;
                JSONArray navigation=new JSONArray();
                for(int i=0;i<10;i++){
                    int target=i%2==0?units-1:0;
                    EpubDocument epub=(EpubDocument)field(activity,"epub");
                    DocumentLocator locator=initial.format.equals("pdf")?DocumentLocator.pdf(target,units,0):epub.locator(target,epub.chapters.get(target).text.length()/2);
                    started=now();instrument.runOnMainSync(()->call(activity,"navigate",new Class<?>[]{DocumentLocator.class,boolean.class},locator,true));
                    waitFor(()->locator.equals(field(activity,"formal")));navigation.put(now()-started);
                }
                result.put("navigation_ms",navigation);
                long readAt=(long)field(activity,"readAt");DocumentLocator formal=(DocumentLocator)field(activity,"formal");
                assertVisible(formal);
                ExecutorService worker=(ExecutorService)field(activity,"worker");
                DocumentSearch.Source provider=(DocumentSearch.Source)call(activity,"searchSource",new Class<?>[]{});
                DocumentSearch search=new DocumentSearch("DOCNEEDLE",0,0);
                started=now();List<DocumentSearch.Hit> batch=worker.submit(()->search.next(provider)).get(120,TimeUnit.SECONDS);result.put("search_first_ms",now()-started).put("first_hits",batch.size());
                started=now();batch=worker.submit(()->search.next(provider)).get(120,TimeUnit.SECONDS);result.put("search_second_ms",now()-started).put("second_hits",batch.size());
                if(!name.equals("pdf-images")&&!name.equals("epub-small"))assertEquals(200,result.getInt("first_hits"));
                DocumentSearch miss=new DocumentSearch("ABSENTPERFTOKEN",0,0);
                started=now();assertTrue(worker.submit(()->miss.next(provider)).get(120,TimeUnit.SECONDS).isEmpty());result.put("miss_ms",now()-started);assertTrue(miss.complete);
                DocumentSearch changedQuery=new DocumentSearch("ANOTHERABSENTTOKEN",0,0);
                started=now();assertTrue(worker.submit(()->changedQuery.next(provider)).get(120,TimeUnit.SECONDS).isEmpty());
                result.put("changed_query_ms",now()-started);assertTrue(changedQuery.complete);
                // A fully cached scan can finish before cancellation is requested.
                // Clear only the session text cache so PDF cancellation measures active parsing.
                PdfDocument pdf=(PdfDocument)field(activity,"pdf");
                if(pdf!=null)worker.submit(pdf::clearSearchCache).get(10,TimeUnit.SECONDS);
                DocumentSearch cancelled=new DocumentSearch("ABSENTPERFTOKEN",0,0);
                Future<?> task=worker.submit(()->{try{cancelled.next(provider);}catch(InterruptedException expected){}catch(Exception e){throw new RuntimeException(e);}});
                Thread.sleep(20);boolean running=!task.isDone();
                if(name.equals("pdf-large"))assertTrue("Cancellation must interrupt an active full-book scan",running);
                started=now();cancelled.cancel();task.get(120,TimeUnit.SECONDS);result.put("cancel_ms",now()-started).put("cancel_was_running",running);
                assertEquals(readAt,(long)field(activity,"readAt"));assertEquals(formal,field(activity,"formal"));
                started=now();closeReader();open(db.loadBooks().get(0));result.put("reopen_ms",now()-started);
                assertEquals(formal,field(activity,"formal"));assertEquals(readAt,(long)field(activity,"readAt"));
                assertVisible(formal);
                closeReader();Thread.sleep(100);result.put("closed_app_mib",Debug.getPss()/1024d);
                db.deleteBook(book);
                result.put("peak_app_mib",meter.peak).put("main_gap_ms",meter.gap);
                Bundle output=new Bundle();output.putString(Instrumentation.REPORT_KEY_STREAMRESULT,"\nXLIB_DOC_PERF "+result+"\n");instrument.sendStatus(2,output);
            } finally {meter.close();closeReader();db.close();}
        }
        assertTrue(source.delete());
    }
}
