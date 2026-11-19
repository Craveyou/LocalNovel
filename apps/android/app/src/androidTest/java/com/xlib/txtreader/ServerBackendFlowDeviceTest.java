package com.xlib.txtreader;

import static org.junit.Assert.*;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.*;
import android.os.*;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;

/** Explicit opt-in: real deployed HTTPS, normal TLS, isolated account and original test books. */
@RunWith(AndroidJUnit4.class)
public class ServerBackendFlowDeviceTest {
    final Instrumentation instrument=InstrumentationRegistry.getInstrumentation();
    final Context context=instrument.getTargetContext();
    final List<Book> books=new ArrayList<>();
    final Map<Long,String> hashes=new HashMap<>();
    final JSONObject report=new JSONObject();
    final JSONArray results=new JSONArray();
    LocalDatabase db;
    Activity reader;
    MainActivity home;
    SyncApiClient api;
    String token,peerToken,device,peer,run,versionName;
    interface Check { boolean get()throws Exception; }
    void waitFor(String label,Check check)throws Exception {
        long end=SystemClock.uptimeMillis()+45000;
        while(SystemClock.uptimeMillis()<end){instrument.waitForIdleSync();if(check.get())return;Thread.sleep(250);}
        fail("Server flow timed out: "+label);
    }
    static Object field(Object target,String name)throws Exception {Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    void invoke(Object target,String name,Class<?>[] types,Object...args){instrument.runOnMainSync(()->{try{Method m=target.getClass().getDeclaredMethod(name,types);m.setAccessible(true);m.invoke(target,args);}catch(Exception e){throw new AssertionError(e);}});}
    byte[] asset(String name)throws Exception {try(InputStream input=instrument.getContext().getAssets().open("documents/"+name);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[65536];int n;while((n=input.read(b))!=-1)out.write(b,0,n);return out.toByteArray();}}
    String hash(byte[] bytes)throws Exception {StringBuilder text=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(bytes))text.append(String.format(Locale.ROOT,"%02x",b&255));return text.toString();}
    void importBook(String name,byte[] bytes)throws Exception {
        File input=File.createTempFile("server-e2e-",".input",context.getCacheDir());try(FileOutputStream out=new FileOutputStream(input)){out.write(bytes);}
        List<Book> published=new ArrayList<>();
        BookImportController<File> imports=new BookImportController<>(new File(context.getFilesDir(),"books"),new BookImportController.Source<File>(){
            public String name(File file){return name;}
            public InputStream open(File file)throws Exception{return new FileInputStream(file);}
            public void validate(File file,String format,ComicArchive.Cancellation cancel)throws Exception{DocumentFormats.validate(context,file,format,cancel);}
        },Runnable::run,Runnable::run,new BookImportController.Listener(){
            public void changed(){} public void publish(Book book){published.add(book);}
            public void finished(int added,int duplicate,int failed){assertEquals(name,1,added);assertEquals(0,failed);}
        });
        try{imports.importBooks(Collections.singletonList(input),Collections.emptyList());}
        finally{imports.close();input.delete();}
        assertEquals(1,published.size());Book book=published.get(0);books.add(book);hashes.put(book.id,hash(bytes));
        assertTrue(db.saveBooks(books,null,0,0));assertEquals(0,book.updatedAt);
    }
    View findView(View node,String label){if(label.contentEquals(node.getContentDescription()==null?"":node.getContentDescription()))return node;if(node instanceof TextView&&label.contentEquals(((TextView)node).getText()))return node;if(node instanceof ViewGroup)for(int i=0;i<((ViewGroup)node).getChildCount();i++){View hit=findView(((ViewGroup)node).getChildAt(i),label);if(hit!=null)return hit;}return null;}
    void input(String hint,String value){instrument.runOnMainSync(()->{List<EditText> fields=new ArrayList<>();collectInputs(home.getWindow().getDecorView(),fields);EditText hit=null;for(EditText input:fields)if(hint.contentEquals(input.getHint()))hit=input;assertNotNull(hint,hit);hit.setText(value);});}
    void collectInputs(View view,List<EditText> inputs){if(view instanceof EditText)inputs.add((EditText)view);if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)collectInputs(((ViewGroup)view).getChildAt(i),inputs);}
    void clickHome(String label)throws Exception {waitFor(label,()->{boolean[] clicked={false};instrument.runOnMainSync(()->{View view=findView(home.getWindow().getDecorView(),label);if(view!=null&&view.isEnabled())clicked[0]=view.performClick();});return clicked[0];});}
    AccessibilityNodeInfo find(AccessibilityNodeInfo node,String label){if(node==null)return null;if(label.contentEquals(node.getText()==null?"":node.getText())||label.contentEquals(node.getContentDescription()==null?"":node.getContentDescription()))return node;for(int i=0;i<node.getChildCount();i++){AccessibilityNodeInfo hit=find(node.getChild(i),label);if(hit!=null)return hit;}return null;}
    void click(String label)throws Exception {waitFor(label,()->{AccessibilityNodeInfo hit=find(instrument.getUiAutomation().getRootInActiveWindow(),label);while(hit!=null&&!hit.isClickable())hit=hit.getParent();return hit!=null&&hit.performAction(AccessibilityNodeInfo.ACTION_CLICK);});}
    void finish(Activity activity)throws Exception {if(activity==null)return;instrument.runOnMainSync(activity::finish);waitFor("activity destroy",activity::isDestroyed);if(!(activity instanceof MainActivity)){ExecutorService worker=(ExecutorService)field(activity,"worker");assertTrue(worker.awaitTermination(15,TimeUnit.SECONDS));}}
    Book saved(Book book){for(Book candidate:db.loadBooks())if(candidate.id==book.id)return candidate;throw new AssertionError("Missing local test book");}
    String path(Book book){return "/v2/progress/"+hashes.get(book.id)+"/"+book.fileSize;}
    JSONArray remote(Book book)throws Exception{return api.requestJson("GET",path(book),null,peerToken,peer).getJSONArray("items");}
    JSONObject only(Book book)throws Exception{JSONArray items=remote(book);assertEquals(1,items.length());return items.getJSONObject(0);}
    DocumentSyncSession session()throws Exception{return (DocumentSyncSession)field(reader,"sync");}
    void launch(Book book)throws Exception {reader=instrument.startActivitySync(new Intent(context,(book.format.equals("cbz")||book.format.equals("cbr"))?ComicPreviewActivity.class:DocumentReaderActivity.class).putExtra("bookId",book.id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));waitFor("ready "+book.sourceName,()->(boolean)field(reader,"ready")&&!(boolean)field(reader,"opening")&&field(reader,"sync")!=null&&session().canRead()&&session().message().contains("完成"));}
    DocumentLocator target(Book book,int which)throws Exception {
        if(book.format.equals("pdf"))return which==0?DocumentLocator.pdf(1,2,0):which==1?DocumentLocator.pdf(0,2,.4):DocumentLocator.pdf(1,2,.3);
        if(book.format.equals("cbz")||book.format.equals("cbr")){ComicDocument doc=(ComicDocument)field(reader,"document");return doc.manifest.locator(book.format,which==0?10:which==1?23:2,0);}
        ReflowDocument doc=(ReflowDocument)field(reader,"epub");return doc.locator(which==1?0:doc.chapters.size()-1,which==0?3:which==1?8:1);
    }
    void navigate(Book book,DocumentLocator target)throws Exception {
        if(book.format.equals("cbz")||book.format.equals("cbr"))invoke(reader,"navigate",new Class<?>[]{int.class,double.class},target.page,target.y);
        else invoke(reader,"navigate",new Class<?>[]{DocumentLocator.class,boolean.class},target,true);
        waitFor("formal navigation",()->target.equals(field(reader,"formal")));
    }
    void refresh()throws Exception {DocumentSyncSession current=session();instrument.runOnMainSync(current::refresh);}
    void documentFlow(Book book)throws Exception {
        assertEquals(0,remote(book).length());launch(book);
        assertEquals("Opening must not manufacture a reading event",0,saved(book).updatedAt);
        DocumentLocator first=target(book,0),second=target(book,1),third=target(book,2);
        navigate(book,first);waitFor("upload "+book.sourceName,()->remote(book).length()==1&&first.equals(DocumentLocator.fromJson(only(book).getJSONObject("locator"))));
        JSONObject uploaded=only(book);assertEquals(device,uploaded.getJSONObject("device").getString("deviceId"));assertEquals(saved(book).updatedAt,uploaded.getLong("readAtMs"));
        assertTrue(db.addDocumentBookmark(book.id,first));assertFalse(db.addDocumentBookmark(book.id,first));
        long peerTime=Math.max(System.currentTimeMillis(),uploaded.getLong("readAtMs")+1);
        JSONObject item=new JSONObject().put("bookHash",hashes.get(book.id)).put("fileSize",book.fileSize).put("locator",second.json()).put("readAtMs",peerTime);
        api.requestJson("POST","/v2/progress/sync",new JSONObject().put("items",new JSONArray().put(item)),peerToken,peer);
        refresh();click(book.format.equals("cbz")||book.format.equals("cbr")?"跳转":"前往");
        waitFor("accept peer",()->second.equals(field(reader,"formal"))&&saved(book).updatedAt==peerTime&&session().canRead());
        refresh();waitFor("acceptance comparison",()->session().message().contains("完成"));assertEquals(peer,only(book).getJSONObject("device").getString("deviceId"));assertEquals(peerTime,only(book).getLong("readAtMs"));
        // Return to an earlier local content anchor with a newer real reading event.
        navigate(book,first);waitFor("return upload",()->only(book).getLong("readAtMs")>peerTime&&first.equals(DocumentLocator.fromJson(only(book).getJSONObject("locator"))));
        if(book.format.equals("kindle")||book.format.equals("cbz")||book.format.equals("cbr")){
            JSONObject before=only(book),bad=new JSONObject(item.toString());bad.put("readAtMs",before.getLong("readAtMs")+1);bad.getJSONObject("locator").put(book.format.equals("kindle")?"textHash":"manifestHash","00".repeat(32));
            SyncApiClient.ApiException rejected=assertThrows(SyncApiClient.ApiException.class,()->api.requestJson("POST","/v2/progress/sync",new JSONObject().put("items",new JSONArray().put(bad)),peerToken,peer));assertEquals(422,rejected.status);assertEquals(before.getString("version"),only(book).getString("version"));
        }
        invoke(reader,book.format.equals("cbz")||book.format.equals("cbr")?"syncDetails":"showSync",new Class<?>[]{});click("删除本书云端进度");click("删除");
        waitFor("cloud deletion",()->remote(book).length()==0);navigate(book,third);refresh();waitFor("session upload paused",()->session().message().contains("暂停"));assertEquals(0,remote(book).length());
        long localTime=saved(book).updatedAt;finish(reader);reader=null;assertEquals(third,saved(book).locator);assertEquals(1,db.documentBookmarks(book.id).size());
        launch(book);waitFor("reopen upload",()->remote(book).length()==1);assertEquals(third,DocumentLocator.fromJson(only(book).getJSONObject("locator")));assertEquals(localTime,only(book).getLong("readAtMs"));
        finish(reader);reader=null;api.requestNoContent("DELETE",path(book),peerToken,peer);assertEquals(0,remote(book).length());
        try(InputStream in=new FileInputStream(book.path)){assertEquals(hashes.get(book.id),hash(in.readAllBytes()));}
        results.put(new JSONObject().put("source",book.sourceName).put("format",book.format).put("passed",true).put("cloudProgressCleaned",true).put("originalPreserved",true));writeReport();
    }
    ProgressSyncCoordinator coordinator()throws Exception{return (ProgressSyncCoordinator)field(home,"syncCoordinator");}
    void refreshTxt()throws Exception {ProgressSyncCoordinator c=coordinator();CountDownLatch done=new CountDownLatch(1);java.util.concurrent.atomic.AtomicReference<SyncActionResult<Void>> result=new java.util.concurrent.atomic.AtomicReference<>();c.refreshRemote(value->{result.set(value);done.countDown();});assertTrue(done.await(40,TimeUnit.SECONDS));assertTrue(result.get().errorCode,result.get().isSuccess());}
    RemoteProgressSnapshot txtRemote(Book book)throws Exception{for(RemoteProgressSnapshot p:api.pullProgress(peerToken,peer))if(p.bookHash.equals(hashes.get(book.id))&&p.fileSize==book.fileSize)return p;return null;}
    void txtFlow(Book original)throws Exception {
        home=(MainActivity)instrument.startActivitySync(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        Book book=null;for(Book b:(List<Book>)field(home,"books"))if(b.id==original.id)book=b;assertNotNull(book);Book active=book;
        invoke(home,"openBook",new Class<?>[]{Book.class},active);waitFor("TXT preparation",()->!coordinator().isPreparing(active.id)&&!(boolean)field(home,"loadingChunk"));assertEquals(0,active.updatedAt);
        invoke(home,"jumpToCatalogOffset",new Class<?>[]{Book.class,long.class},active,3000L);refreshTxt();waitFor("TXT upload",()->txtRemote(active)!=null&&txtRemote(active).offset==active.offset);
        RemoteProgressSnapshot first=txtRemote(active);assertEquals(device,first.sourceDeviceId);assertTrue(db.addBookmark(active.id,active.offset));
        long peerTime=Math.max(System.currentTimeMillis(),first.readAtMs+1);
        api.syncProgress(peerToken,peer,new LocalProgressSnapshot(active.id,hashes.get(active.id),active.fileSize,0,peerTime,0));refreshTxt();click("跳转");
        waitFor("TXT accept peer",()->active.updatedAt==peerTime&&!coordinator().isPreparing(active.id));refreshTxt();assertEquals(peerTime,txtRemote(active).readAtMs);assertEquals(peer,txtRemote(active).sourceDeviceId);
        invoke(home,"jumpToCatalogOffset",new Class<?>[]{Book.class,long.class},active,6000L);refreshTxt();waitFor("TXT return upload",()->txtRemote(active).readAtMs>peerTime);
        invoke(home,"confirmDeleteBookCloudProgress",new Class<?>[]{Book.class},active);click("删除");waitFor("TXT deletion",()->txtRemote(active)==null);
        invoke(home,"jumpToCatalogOffset",new Class<?>[]{Book.class,long.class},active,9000L);refreshTxt();assertNull(txtRemote(active));assertEquals(1,db.loadBookmarks(active.id).size());
        finish(home);home=null;long time=saved(active).updatedAt;long offset=saved(active).offset;
        home=(MainActivity)instrument.startActivitySync(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Book reopen=null;for(Book b:(List<Book>)field(home,"books"))if(b.id==active.id)reopen=b;assertNotNull(reopen);
        invoke(home,"openBook",new Class<?>[]{Book.class},reopen);waitFor("TXT reopened",()->!coordinator().isPreparing(active.id));refreshTxt();waitFor("TXT reopen upload",()->txtRemote(active)!=null);assertEquals(time,txtRemote(active).readAtMs);assertEquals(offset,txtRemote(active).offset);
        finish(home);home=null;api.deleteBookProgress(peerToken,peer,new BookKey(hashes.get(active.id),active.fileSize));assertNull(txtRemote(active));
        try(InputStream input=new FileInputStream(active.path)){assertEquals(hashes.get(active.id),hash(input.readAllBytes()));}
        results.put(new JSONObject().put("source",active.sourceName).put("format","txt").put("passed",true).put("cloudProgressCleaned",true).put("originalPreserved",true));writeReport();
    }
    void writeReport()throws Exception {report.put("books",results);try(FileOutputStream out=new FileOutputStream(new File(context.getExternalFilesDir(null),"server-e2e-"+run+".json"))){out.write(report.toString(2).getBytes(StandardCharsets.UTF_8));}}
    void verifyPreviousRun(String previous)throws Exception {
        if(previous==null||previous.isEmpty())return;
        assertTrue(previous.matches("android-e2e-[0-9]{13}-[0-9a-f]{8}"));
        String auditDevice=UUID.randomUUID().toString(),auditToken=api.startSync(previous+"@example.com",auditDevice,"Android清理复核",versionName).token;
        int remaining=0,activeDevices=0;
        try{
            for(RemoteProgressSnapshot state:api.pullProgress(auditToken,auditDevice)){remaining++;api.deleteBookProgress(auditToken,auditDevice,new BookKey(state.bookHash,state.fileSize));}
            List<String> names=new ArrayList<>(Arrays.asList("text-rotated.pdf","reflow.epub","comic-basic.cbz","comic-basic-rar4.cbr","comic-basic-rar5.cbr","comic-basic-rar4-solid.cbr"));names.addAll(Arrays.asList(KindleDeviceTest.NAMES));
            for(String name:names){byte[] original=asset(name);String path="/v2/progress/"+hash(original)+"/"+original.length;JSONArray states=api.requestJson("GET",path,null,auditToken,auditDevice).getJSONArray("items");if(states.length()>0){remaining++;api.requestNoContent("DELETE",path,auditToken,auditDevice);}assertEquals(0,api.requestJson("GET",path,null,auditToken,auditDevice).getJSONArray("items").length());}
            for(SyncDevice item:api.listDevices(auditToken,auditDevice))if(!item.deviceId.equals(auditDevice)&&!item.revoked){activeDevices++;api.revokeDevice(auditToken,auditDevice,item.deviceId);}
            assertTrue(api.pullProgress(auditToken,auditDevice).isEmpty());
            report.put("previousRunAudit",new JSONObject().put("run",previous).put("remainingProgressBeforeAudit",remaining).put("activePreviousDevicesBeforeAudit",activeDevices).put("cleaned",true));
        }finally{api.revokeDevice(auditToken,auditDevice,auditDevice);}
    }
    @Test public void deployedBackendAllFormatsThroughRealReaderSessions()throws Exception {
        Bundle args=InstrumentationRegistry.getArguments();String base=args.getString("serverUrl");Assume.assumeNotNull(base);
        assertEquals("isolated-test-data",args.getString("allowServerWrites"));assertEquals(SyncServerConfig.DEFAULT_URL,base);
        assertTrue(Build.HARDWARE.contains("ranchu")||Build.HARDWARE.contains("goldfish"));
        run="android-e2e-"+System.currentTimeMillis()+"-"+UUID.randomUUID().toString().substring(0,8);
        context.deleteDatabase("xlib.db");context.getSharedPreferences("xlib_reader",0).edit().clear().commit();db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0));
        android.content.pm.PackageInfo info=context.getPackageManager().getPackageInfo(context.getPackageName(),0);versionName=info.versionName;
        api=new SyncApiClient(base);api.health();report.put("run",run).put("server",base).put("versionName",versionName).put("versionCode",info.versionCode).put("normalTls",true);
        try {
            verifyPreviousRun(args.getString("previousRun"));
            importBook("server-flow.txt",("第一章 服务器全流程 "+run+"\n测试阅读与复制。\n").repeat(800).getBytes(StandardCharsets.UTF_8));
            for(String name:new String[]{"text-rotated.pdf","reflow.epub","comic-basic.cbz","comic-basic-rar4.cbr","comic-basic-rar5.cbr","comic-basic-rar4-solid.cbr"})importBook(name,asset(name));
            for(String name:KindleDeviceTest.NAMES)importBook(name,asset(name));assertEquals(13,books.size());
            home=(MainActivity)instrument.startActivitySync(new Intent(context,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));invoke(home,"showSettingsPage",new Class<?>[]{Book.class,int.class},null,2);
            input("请输入同步邮箱",run+"@example.com");input("请输入当前设备名称","Android服务器流程A");clickHome("同步刷新");
            SyncTokenStore credentials=new SyncTokenStore(context.getSharedPreferences("xlib_reader",0),db);waitFor("registration through settings",()->credentials.token()!=null&&coordinator().state().lastSuccessAtMs>0);token=credentials.token();device=credentials.deviceId();
            peer=UUID.randomUUID().toString();peerToken=api.startSync(run+"@example.com",peer,"Android服务器流程B",versionName).token;assertEquals(2,api.listDevices(token,device).size());assertTrue(api.pullProgress(token,device).isEmpty());finish(home);home=null;
            for(Book book:books)if(!book.format.equals("txt"))documentFlow(book);
            txtFlow(books.get(0));assertTrue(api.pullProgress(token,device).isEmpty());report.put("passed",true);
        } catch(Exception|AssertionError failure) {
            report.put("passed",false).put("failure",failure.getClass().getSimpleName()+": "+failure.getMessage());throw failure;
        } finally {
            finish(reader);reader=null;finish(home);home=null;
            boolean cleaned=true;JSONArray cleanupErrors=new JSONArray();
            if(token!=null&&device!=null){for(Book book:books)try{
                    // Respect the deployed delete rate limit: do not delete already-empty rows again.
                    if(book.format.equals("txt")){for(RemoteProgressSnapshot p:api.pullProgress(token,device))if(p.bookHash.equals(hashes.get(book.id))&&p.fileSize==book.fileSize)api.deleteBookProgress(token,device,new BookKey(p.bookHash,p.fileSize));}
                    else {JSONArray remaining=api.requestJson("GET",path(book),null,token,device).getJSONArray("items");if(remaining.length()>0)api.requestNoContent("DELETE",path(book),token,device);assertEquals(0,api.requestJson("GET",path(book),null,token,device).getJSONArray("items").length());}
                }catch(Exception|AssertionError e){cleaned=false;cleanupErrors.put(cleanupError(book.sourceName,e));}
                if(peer!=null&&peerToken!=null){try{api.revokeDevice(token,device,peer);SyncApiClient.ApiException error=assertThrows(SyncApiClient.ApiException.class,()->api.listDevices(peerToken,peer));assertTrue(error.status==401||error.status==403);}catch(Exception|AssertionError e){cleaned=false;cleanupErrors.put(cleanupError("peer revoke",e));}}
                try{api.revokeDevice(token,device,device);}catch(Exception e){cleaned=false;cleanupErrors.put(cleanupError("self revoke",e));}
            }
            report.put("cleanupErrors",cleanupErrors).put("cloudProgressAndDeviceTokensCleaned",cleaned).put("accountMetadataRetained",true);writeReport();new SyncTokenStore(context.getSharedPreferences("xlib_reader",0),db).clear();db.close();if(report.optBoolean("passed"))assertTrue("Clean up only this run's cloud progress and device tokens: "+cleanupErrors,cleaned);
        }
    }
    JSONObject cleanupError(String stage,Throwable error)throws Exception{JSONObject value=new JSONObject().put("stage",stage).put("type",error.getClass().getSimpleName());if(error instanceof SyncApiClient.ApiException)value.put("httpStatus",((SyncApiClient.ApiException)error).status).put("code",((SyncApiClient.ApiException)error).code);return value;}
}
