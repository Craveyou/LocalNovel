package com.xlib.txtreader;

import android.os.Bundle;
import android.os.SystemClock;
import android.util.Base64;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.Assume;
import static org.junit.Assert.*;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.cert.CertificateFactory;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;

/** Opt-in cross-platform test, pinned to one temporary localhost certificate. */
@RunWith(AndroidJUnit4.class)
public class DocumentInteropDeviceTest {
    @Test public void exchangeOriginalDocumentCoordinatesWithIOSAndPostgres()throws Exception{
        Bundle args=InstrumentationRegistry.getArguments();String base=args.getString("interopUrl");
        Assume.assumeTrue("Requires the disposable HTTPS/PostgreSQL harness",base!=null);
        assertTrue(android.os.Build.HARDWARE.contains("ranchu")||android.os.Build.HARDWARE.contains("goldfish"));
        assertTrue(base.matches("https://localhost:[0-9]+"));
        byte[] certificate=Base64.decode(args.getString("interopCertificate"),Base64.DEFAULT);
        KeyStore trusted=KeyStore.getInstance(KeyStore.getDefaultType());trusted.load(null);
        trusted.setCertificateEntry("test-localhost",CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(certificate)));
        TrustManagerFactory managers=TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());managers.init(trusted);
        SSLContext ssl=SSLContext.getInstance("TLS");ssl.init(null,managers.getTrustManagers(),null);
        javax.net.ssl.SSLSocketFactory previous=HttpsURLConnection.getDefaultSSLSocketFactory();HttpsURLConnection.setDefaultSSLSocketFactory(ssl.getSocketFactory());
        try{
            int phase=Integer.parseInt(args.getString("interopPhase","1"));String run=args.getString("interopRun");
            String device=UUID.nameUUIDFromBytes((run+"android-a").getBytes(StandardCharsets.UTF_8)).toString();
            SyncApiClient api=new SyncApiClient(base);
            String email=run+"@example.com";
            String token=api.startSync(email,device,"Android interop device name longer than twenty","0.12.0").token;
            String other=UUID.nameUUIDFromBytes((run+"android-b").getBytes(StandardCharsets.UTF_8)).toString();
            String otherToken=phase==1?api.startSync(email,other,"Second Android","0.12.0").token:null;
            JSONArray vectors=new JSONArray(new String(asset("documents/coordinates.json"),StandardCharsets.UTF_8));
            for(int index=0;index<2;index++){
                JSONObject vector=vectors.getJSONObject(index);byte[] original=asset("documents/"+vector.getString("file"));
                StringBuilder digest=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(original))digest.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
                assertEquals(vector.getString("bookHash"),digest.toString());assertEquals(vector.getLong("fileSize"),original.length);
                DocumentLocator target=DocumentLocator.fromJson(vector.getJSONObject("locator"));
                Book book=new Book();book.format=target.format;book.fileSize=original.length;book.locator=target;book.updatedAt=0;
                String path="/v2/progress/"+digest+"/"+original.length;
                DocumentSyncSession.Connection connection=new DocumentSyncSession.Connection(){
                    public boolean enabled(){return true;}
                    public String identity(){return run+device;}
                    public JSONObject get(String p)throws Exception{return api.requestJson("GET",p,null,token,device);}
                    public JSONObject post(JSONObject body)throws Exception{return api.requestJson("POST","/v2/progress/sync",body,token,device);}
                    public void delete(String p)throws Exception{api.requestNoContent("DELETE",p,token,device);}
                };
                if(phase==1){
                    book.updatedAt=System.currentTimeMillis()-5000;
                    CountDownLatch uploaded=new CountDownLatch(1);
                    DocumentSyncSession session=new DocumentSyncSession(book,digest.toString(),new DocumentSyncSession.Listener(){
                        public void remote(DocumentLocator l,long t,Runnable yes,Runnable no){fail("Empty test database unexpectedly had remote progress");}
                        public void state(String text){if(text.equals("同步比较完成"))uploaded.countDown();}
                    },connection);
                    session.resume();assertTrue("Android upload did not complete",uploaded.await(15,TimeUnit.SECONDS));session.close();
                    JSONObject fetched=api.requestJson("GET",path,null,otherToken,other).getJSONArray("items").getJSONObject(0);
                    assertEquals(target,DocumentLocator.fromJson(fetched.getJSONObject("locator")));
                }else{
                    JSONObject state=api.requestJson("GET",path,null,token,device).getJSONArray("items").getJSONObject(0);
                    assertEquals("ios",state.getJSONObject("device").getString("platform"));
                    DocumentLocator expected=index==0?DocumentLocator.pdf(0,2,.5):DocumentLocator.fromJson(vectors.getJSONObject(2).getJSONObject("locator"));
                    assertEquals(expected,DocumentLocator.fromJson(state.getJSONObject("locator")));
                    CountDownLatch accepted=new CountDownLatch(1);
                    DocumentSyncSession session=new DocumentSyncSession(book,digest.toString(),new DocumentSyncSession.Listener(){
                        public void remote(DocumentLocator locator,long time,Runnable yes,Runnable no){assertEquals(expected,locator);book.locator=locator;book.updatedAt=time;yes.run();accepted.countDown();}
                        public void state(String text){}
                    },connection);
                    session.resume();assertTrue("Android did not offer iOS position",accepted.await(15,TimeUnit.SECONDS));session.close();
                    // A later reread moves backwards in content and still wins by time.
                    DocumentLocator reread=index==0?DocumentLocator.pdf(1,2,0):target;
                    JSONObject item=new JSONObject().put("bookHash",digest.toString()).put("fileSize",original.length).put("locator",reread.json()).put("readAtMs",Math.max(System.currentTimeMillis(),book.updatedAt+1));
                    JSONObject response=api.requestJson("POST","/v2/progress/sync",new JSONObject().put("items",new JSONArray().put(item)),token,device);
                    assertEquals("accepted",response.getJSONArray("results").getJSONObject(0).getString("decision"));
                }
            }
            assertEquals(0,api.pullProgress(token,device).size());
        }finally{HttpsURLConnection.setDefaultSSLSocketFactory(previous);}
    }
    private byte[] asset(String path)throws Exception{try(java.io.InputStream in=InstrumentationRegistry.getInstrumentation().getContext().getAssets().open(path)){java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)out.write(b,0,n);return out.toByteArray();}}
}
