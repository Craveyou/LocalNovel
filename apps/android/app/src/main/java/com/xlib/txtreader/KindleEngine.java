package com.xlib.txtreader;

import android.annotation.SuppressLint;
import android.content.Context;
import android.os.*;
import android.webkit.*;
import android.util.Base64;
import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** One offline VM per parse. Only trusted shared code is ever loaded in this host. */
final class KindleEngine {
    private final File source;
    private final ComicArchive.Cancellation cancellation;
    private final CountDownLatch done=new CountDownLatch(1);
    private final AtomicBoolean closed=new AtomicBoolean();
    private volatile String output,error;
    private WebView web;
    private KindleEngine(File source,ComicArchive.Cancellation cancel){this.source=source;this.cancellation=cancel;}
    static String parse(Context context,File source,ComicArchive.Cancellation cancel)throws Exception {
        if(Looper.myLooper()==Looper.getMainLooper())throw new IOException("Kindle 解析必须在后台执行");
        ComicArchive.check(cancel);
        KindleEngine engine=new KindleEngine(source,cancel);Handler main=new Handler(Looper.getMainLooper());
        main.post(()->engine.start(context.getApplicationContext()));
        try {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(90);
            while(!engine.done.await(50,TimeUnit.MILLISECONDS)) {
                ComicArchive.check(cancel);
                if(System.nanoTime()>deadline)throw new IOException("Kindle 解析超时");
            }
            ComicArchive.check(cancel);
            if(engine.error!=null||engine.output==null)throw new IOException(engine.error==null?"Kindle 解析失败":engine.error);
            return engine.output;
        } finally {engine.closed.set(true);main.post(engine::dispose);}
    }
    @SuppressLint("SetJavaScriptEnabled") private void start(Context context) {
        if(closed.get())return;
        try {
            web=new WebView(context);web.getSettings().setJavaScriptEnabled(true);
            web.getSettings().setAllowFileAccess(false);web.getSettings().setAllowContentAccess(false);
            web.getSettings().setBlockNetworkLoads(true);web.getSettings().setDomStorageEnabled(false);
            web.getSettings().setCacheMode(WebSettings.LOAD_NO_CACHE);
            web.addJavascriptInterface(this,"KindleHost");
            web.setWebViewClient(new WebViewClient(){
                @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){
                    try {
                        if(request.getUrl().toString().equals("https://kindle-core.xlib.invalid/core.js"))
                            return new WebResourceResponse("application/javascript","UTF-8",context.getAssets().open("kindle-core.js"));
                    }catch(Exception failure){fail("Kindle 公共核心资源缺失");}
                    return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));
                }
                @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){return true;}
                @Override public boolean shouldOverrideUrlLoading(WebView view,String url){return true;}
                @Override public void onPageFinished(WebView view,String url){
                    if(closed.get())return;
                    view.evaluateJavascript("(function(){try{var result=XLibKindle.parse({size:"+source.length()+",read:function(o,n){var s=KindleHost.read(o,n);if(s===null)throw Error('读取失败或已取消');return Uint8Array.from(atob(s),function(c){return c.charCodeAt(0);});}},function(){return KindleHost.cancelled();});KindleHost.complete(JSON.stringify(result));}catch(e){KindleHost.fail(String(e));}})()",null);
                }
            });
            web.loadDataWithBaseURL("https://kindle-core.xlib.invalid/","<!doctype html><meta charset=utf-8><meta http-equiv=Content-Security-Policy content=\"default-src 'none'; script-src https://kindle-core.xlib.invalid; connect-src 'none'\"><script src=\"https://kindle-core.xlib.invalid/core.js\"></script>","text/html","UTF-8",null);
        }catch(Exception failure){fail("Kindle 解析环境不可用："+failure.getMessage());}
    }
    @JavascriptInterface public boolean cancelled(){return closed.get()||cancellation.cancelled();}
    @JavascriptInterface public String read(long offset,int count){
        try {
            if(cancelled()||offset<0||count<0||count>16*1024*1024||offset>source.length()-count)throw new IOException();
            byte[] bytes=new byte[count];try(RandomAccessFile input=new RandomAccessFile(source,"r")){input.seek(offset);input.readFully(bytes);}
            return Base64.encodeToString(bytes,Base64.NO_WRAP);
        }catch(Exception failure){return null;}
    }
    @JavascriptInterface public void complete(String value){if(!closed.get())output=value;done.countDown();}
    @JavascriptInterface public void fail(String message){error=message;done.countDown();}
    private void dispose(){if(web!=null){web.stopLoading();web.removeJavascriptInterface("KindleHost");web.destroy();web=null;}}
}
