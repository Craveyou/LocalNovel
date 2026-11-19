package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.os.Looper;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

@RunWith(RobolectricTestRunner.class) @Config(sdk=35)
public class DocumentSyncSessionTest {
    final String hash="ab".repeat(32);
    final Book book=new Book();
    DocumentSyncSession session;
    final List<Runnable> accepted=new ArrayList<>(),rejected=new ArrayList<>();
    final List<DocumentLocator> prompts=new ArrayList<>();
    public DocumentSyncSessionTest(){book.id=1;book.format="pdf";book.fileSize=120;book.locator=DocumentLocator.pdf(0,4,0);book.updatedAt=5;}
    JSONObject state(DocumentLocator p,long time)throws Exception{
        return new JSONObject().put("bookHash",hash).put("fileSize",120).put("locator",p.json()).put("progress",p.progress()).put("readAtMs",time).put("version","7")
            .put("device",new JSONObject().put("deviceId","00000000-0000-4000-8000-000000000001").put("deviceName","远端设备名称".repeat(5)).put("platform","ios"));
    }
    final class Wire implements DocumentSyncSession.Connection {
        volatile JSONObject remote; volatile String scope="account-a"; volatile int gets,posts,deletes;volatile boolean enabled=true;
        CountDownLatch entered,release;
        final List<String> order=Collections.synchronizedList(new ArrayList<>());
        public boolean enabled(){return enabled;}
        public String identity(){return scope;}
        public JSONObject get(String path)throws Exception{gets++;order.add("GET");if(entered!=null){entered.countDown();assertTrue(release.await(5,TimeUnit.SECONDS));}return new JSONObject().put("items",remote==null?new JSONArray():new JSONArray().put(remote));}
        public JSONObject post(JSONObject body)throws Exception{posts++;order.add("POST");JSONObject item=body.getJSONArray("items").getJSONObject(0);assertEquals(4,item.length());assertFalse(body.toString().contains("password"));remote=state(DocumentLocator.fromJson(item.getJSONObject("locator")),item.getLong("readAtMs"));return new JSONObject().put("results",new JSONArray().put(new JSONObject().put("state",remote)));}
        public void delete(String path){deletes++;order.add("DELETE");remote=null;}
    }
    void open(Wire wire){session=new DocumentSyncSession(book,hash,new DocumentSyncSession.Listener(){
        public void remote(DocumentLocator p,long time,Runnable yes,Runnable no){prompts.add(p);accepted.add(yes);rejected.add(no);}
        public void state(String text){}
    },wire);session.resume();}
    void waitFor(BooleanSupplier condition)throws Exception{
        long end=System.nanoTime()+5_000_000_000L;
        while(!condition.getAsBoolean()&&System.nanoTime()<end){Shadows.shadowOf(Looper.getMainLooper()).idle();Thread.sleep(5);}
        Shadows.shadowOf(Looper.getMainLooper()).idle();assertTrue("sync operation timed out",condition.getAsBoolean());
    }
    @After public void close(){if(session!=null)session.close();}
    @Test public void closeWhileRefreshIsPreparingNeverSubmitsToClosedExecutor()throws Exception {
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        java.util.concurrent.atomic.AtomicReference<Throwable> failure=new java.util.concurrent.atomic.AtomicReference<>();
        Wire wire=new Wire();
        session=new DocumentSyncSession(book,hash,new DocumentSyncSession.Listener(){
            public void state(String text){fail("Closed session must not publish a state");}
            public void remote(DocumentLocator p,long time,Runnable yes,Runnable no){fail("Closed session must not prompt");}
        },new DocumentSyncSession.Connection(){
            public boolean enabled(){entered.countDown();try{assertTrue(release.await(5,TimeUnit.SECONDS));}catch(InterruptedException error){throw new AssertionError(error);}return true;}
            public String identity(){return wire.identity();}
            public JSONObject get(String path)throws Exception{return wire.get(path);}
            public JSONObject post(JSONObject body)throws Exception{return wire.post(body);}
            public void delete(String path){wire.delete(path);}
        });
        Thread preparing=new Thread(()->{try{session.resume();}catch(Throwable error){failure.set(error);}});
        preparing.start();assertTrue(entered.await(5,TimeUnit.SECONDS));
        try{session.close();}finally{release.countDown();}
        preparing.join(5000);assertFalse(preparing.isAlive());assertNull(failure.get());
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(30,TimeUnit.SECONDS);
        assertEquals(0,wire.gets);assertEquals(0,wire.posts);assertTrue(session.canRead());
    }
    @Test public void readingEventDuringInFlightRequestIsCoalescedInsteadOfDropped()throws Exception {
        Wire wire=new Wire();open(wire);waitFor(()->wire.posts==1&&session.message().contains("完成"));
        wire.entered=new CountDownLatch(1);wire.release=new CountDownLatch(1);session.refresh();
        assertTrue(wire.entered.await(5,TimeUnit.SECONDS));book.updatedAt=200;session.moved();wire.release.countDown();
        waitFor(()->wire.gets>=3&&wire.posts==2&&session.message().contains("完成"));assertEquals(2,wire.posts);assertEquals(200,wire.remote.getLong("readAtMs"));
    }
    @Test public void newerRemoteWaitsForOneChoiceAndStaleChoiceCannotAffectResumedSession()throws Exception{
        Wire wire=new Wire();wire.remote=state(DocumentLocator.pdf(2,4,.5),100);open(wire);
        waitFor(()->prompts.size()==1);assertFalse(session.canRead());assertEquals(0,book.locator.page);
        session.refresh();assertEquals(1,wire.gets);assertEquals(0,wire.posts);
        Runnable stale=rejected.get(0);session.pause();session.resume();waitFor(()->prompts.size()==2);
        stale.run();assertFalse(session.canRead());
        rejected.get(1).run();assertTrue(session.canRead());assertEquals(5,book.updatedAt);
    }
    @Test public void backgroundedPullCannotUploadAndResumptionComparesAgain()throws Exception{
        Wire wire=new Wire();wire.entered=new CountDownLatch(1);wire.release=new CountDownLatch(1);open(wire);
        assertTrue(wire.entered.await(5,TimeUnit.SECONDS));session.pause();wire.release.countDown();
        waitFor(()->session.canRead());assertEquals(0,wire.posts);
        wire.entered=null;session.resume();waitFor(()->wire.posts==1);assertTrue(wire.gets>=2);
    }
    @Test public void successfulCloudDeletionPausesOnlyThisSessionAcrossBackgroundAndRefresh()throws Exception{
        Wire wire=new Wire();open(wire);waitFor(()->wire.posts==1&&session.message().contains("完成"));
        session.delete();waitFor(()->wire.deletes==1&&session.message().contains("暂停"));
        book.updatedAt=200;session.moved();session.refresh();waitFor(()->wire.gets>=2&&session.message().contains("暂停"));
        session.pause();session.resume();waitFor(()->wire.gets>=3&&session.message().contains("暂停"));
        assertEquals(1,wire.posts);assertTrue(wire.order.indexOf("POST")<wire.order.indexOf("DELETE"));
        session.close();open(wire);waitFor(()->wire.posts==2);
    }
    @Test public void incompatibleComicManifestBlocksEvenOlderRemoteBeforeTimestampComparison()throws Exception {
        book.format="cbr";book.locator=DocumentLocator.comic("cbr","aa".repeat(32),"bb".repeat(32),0,3,0);
        Wire wire=new Wire();wire.remote=state(DocumentLocator.comic("cbr","cc".repeat(32),"bb".repeat(32),0,3,0),1);
        session=new DocumentSyncSession(book,hash,new DocumentSyncSession.Listener(){public void state(String text){}public void remote(DocumentLocator p,long time,Runnable yes,Runnable no){fail("Incompatible manifest must not prompt");}},wire);
        session.validateWith(p->p.manifestHash.equals(book.locator.manifestHash));session.resume();
        waitFor(()->session.message().contains("不可用"));assertEquals(0,wire.posts);assertEquals(5,book.updatedAt);
        wire.remote=state(book.locator,1);session.refresh();waitFor(()->wire.posts==1);assertEquals("GET",wire.order.get(0));
        session.temporary(true);book.updatedAt=50;int reads=wire.gets;session.moved();session.refresh();Shadows.shadowOf(Looper.getMainLooper()).idle();assertEquals(reads,wire.gets);assertEquals(1,wire.posts);
        session.temporary(false);session.refresh();
        try{waitFor(()->wire.posts==2);}catch(AssertionError failure){throw new AssertionError("posts="+wire.posts+", gets="+wire.gets+", state="+session.message()+", remote="+wire.remote,failure);}
        session.delete();waitFor(()->wire.deletes==1&&session.message().contains("暂停"));book.updatedAt=60;session.moved();session.refresh();waitFor(()->session.message().contains("暂停"));assertEquals(2,wire.posts);
    }
    @Test public void malformedLocatorAndChangedAccountNeverUploadOrPrompt()throws Exception{
        Wire wire=new Wire();wire.remote=state(DocumentLocator.pdf(2,4,0),100);wire.remote.getJSONObject("locator").put("page",2.5);open(wire);
        waitFor(()->session.message().contains("不可用"));assertTrue(prompts.isEmpty());assertEquals(0,wire.posts);assertEquals(0,book.locator.page);
        session.close();wire.remote=null;wire.entered=new CountDownLatch(1);wire.release=new CountDownLatch(1);open(wire);
        assertTrue(wire.entered.await(5,TimeUnit.SECONDS));wire.scope="account-b";wire.release.countDown();
        waitFor(()->session.message().contains("不可用"));assertEquals(0,wire.posts);assertTrue(session.canRead());
    }
}
