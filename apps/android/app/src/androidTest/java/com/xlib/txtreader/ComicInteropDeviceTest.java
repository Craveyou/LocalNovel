package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.os.*;
import android.util.Base64;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.CertificateFactory;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import javax.net.ssl.*;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;

/** Real HTTPS/PostgreSQL protocol run, isolated credentials and certificate per invocation. */
@RunWith(AndroidJUnit4.class)
public class ComicInteropDeviceTest {
    byte[] asset(String path)throws Exception {try(InputStream in=InstrumentationRegistry.getInstrumentation().getContext().getAssets().open(path)){ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)out.write(b,0,n);return out.toByteArray();}}
    void waitFor(java.util.function.BooleanSupplier check)throws Exception {long end=SystemClock.uptimeMillis()+15000;while(!check.getAsBoolean()&&SystemClock.uptimeMillis()<end)Thread.sleep(25);assertTrue("Comic HTTPS session timed out",check.getAsBoolean());}
    @Test public void originalComicIdentityManifestConflictTimePriorityAndSessionDeletion()throws Exception {
        Bundle args=InstrumentationRegistry.getArguments();String base=args.getString("interopUrl");Assume.assumeNotNull(base);assertTrue(base.matches("https://localhost:[0-9]+"));assertTrue(android.os.Build.HARDWARE.contains("ranchu")||android.os.Build.HARDWARE.contains("goldfish"));
        KeyStore trusted=KeyStore.getInstance(KeyStore.getDefaultType());trusted.load(null);trusted.setCertificateEntry("one-test",CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(Base64.decode(args.getString("interopCertificate"),Base64.DEFAULT))));TrustManagerFactory managers=TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());managers.init(trusted);SSLContext ssl=SSLContext.getInstance("TLS");ssl.init(null,managers.getTrustManagers(),null);SSLSocketFactory previous=HttpsURLConnection.getDefaultSSLSocketFactory();HttpsURLConnection.setDefaultSSLSocketFactory(ssl.getSocketFactory());
        try{
            String run=args.getString("interopRun"),first=UUID.randomUUID().toString(),second=UUID.randomUUID().toString();SyncApiClient api=new SyncApiClient(base);String email=run+"-comic@example.com";
            String token=api.startSync(email,first,"Android comic first","0.13.1").token,otherToken=api.startSync(email,second,"Android comic second","0.13.1").token;
            JSONObject pageFixture=new JSONObject(new String(asset("documents/comic-basic.json"),StandardCharsets.UTF_8));
            for(String name:new String[]{"comic-basic.cbz","comic-basic-rar4.cbr","comic-basic-rar5.cbr","comic-basic-rar4-solid.cbr"}){
                JSONObject fixture=new JSONObject(new String(asset("documents/"+name.replace(".cbz",".json").replace(".cbr",".json")),StandardCharsets.UTF_8));byte[] original=asset("documents/"+name);StringBuilder digest=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(original))digest.append(String.format(Locale.ROOT,"%02x",b&255));assertEquals(fixture.getString("bookHash"),digest.toString());
                String hash=digest.toString(),path="/v2/progress/"+hash+"/"+original.length;String format=fixture.getString("format"),manifest=fixture.getString("manifestHash");
                DocumentLocator end=DocumentLocator.comic(format,manifest,pageFixture.getJSONArray("pages").getJSONObject(23).getString("pageKey"),23,24,0);
                long time=System.currentTimeMillis()-10000;JSONObject item=new JSONObject().put("bookHash",hash).put("fileSize",original.length).put("locator",end.json()).put("readAtMs",time);
                api.requestJson("POST","/v2/progress/sync",new JSONObject().put("items",new JSONArray().put(item)),token,first);
                assertEquals(end,DocumentLocator.fromJson(api.requestJson("GET",path,null,otherToken,second).getJSONArray("items").getJSONObject(0).getJSONObject("locator")));
                DocumentLocator reread=DocumentLocator.comic(format,manifest,pageFixture.getJSONArray("pages").getJSONObject(10).getString("pageKey"),10,24,.5000005);
                item.put("locator",reread.json()).put("readAtMs",time+1000);JSONObject response=api.requestJson("POST","/v2/progress/sync",new JSONObject().put("items",new JSONArray().put(item)),otherToken,second);assertEquals("accepted",response.getJSONArray("results").getJSONObject(0).getString("decision"));
                JSONObject bad=new JSONObject(item.toString());bad.getJSONObject("locator").put("manifestHash","00".repeat(32));for(long candidate:new long[]{time-1000,time+2000}){bad.put("readAtMs",candidate);SyncApiClient.ApiException error=assertThrows(SyncApiClient.ApiException.class,()->api.requestJson("POST","/v2/progress/sync",new JSONObject().put("items",new JSONArray().put(bad)),token,first));assertEquals(422,error.status);}
                Book book=new Book();book.format=format;book.fileSize=original.length;book.locator=end;book.updatedAt=time;AtomicInteger posts=new AtomicInteger(),prompts=new AtomicInteger();
                DocumentSyncSession.Connection wire=new DocumentSyncSession.Connection(){public boolean enabled(){return true;}public String identity(){return run+first;}public JSONObject get(String p)throws Exception{return api.requestJson("GET",p,null,token,first);}public JSONObject post(JSONObject body)throws Exception{posts.incrementAndGet();return api.requestJson("POST","/v2/progress/sync",body,token,first);}public void delete(String p)throws Exception{api.requestNoContent("DELETE",p,token,first);}};
                try(DocumentSyncSession session=new DocumentSyncSession(book,hash,new DocumentSyncSession.Listener(){public void state(String text){}public void remote(DocumentLocator p,long t,Runnable yes,Runnable no){if(!reread.equals(p)){no.run();return;}book.locator=p;book.updatedAt=t;yes.run();prompts.incrementAndGet();}},wire)){
                    session.validateWith(p->manifest.equals(p.manifestHash)&&p.pageCount==24&&pageFixture.optJSONArray("pages").optJSONObject(p.page).optString("pageKey").equals(p.pageKey));session.resume();waitFor(()->prompts.get()==1);assertEquals(time+1000,book.updatedAt);assertEquals(.500001,book.locator.y,0);assertEquals(0,posts.get());
                    session.delete();waitFor(()->session.message().contains("已删除"));book.updatedAt=time+3000;session.moved();session.refresh();waitFor(()->session.message().contains("暂停"));assertEquals(0,posts.get());assertEquals(0,api.requestJson("GET",path,null,otherToken,second).getJSONArray("items").length());
                }
            }
            assertTrue(api.pullProgress(token,first).isEmpty());
        }finally{HttpsURLConnection.setDefaultSSLSocketFactory(previous);}
    }
}
