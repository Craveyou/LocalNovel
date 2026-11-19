package com.xlib.txtreader;

import android.annotation.SuppressLint;
import android.content.Context;
import android.net.Uri;
import android.view.MotionEvent;
import android.view.GestureDetector;
import android.view.ActionMode;
import android.view.Menu;
import android.view.MenuItem;
import android.graphics.Rect;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Sanitized local XHTML; authored scripts and all automatic remote requests are blocked. */
@SuppressLint("SetJavaScriptEnabled")
final class EpubPageView extends WebView {
    interface Listener { void moved(int offset); void selected(String text); void link(String href); default void tapped(){} default boolean dismissMenus(){return false;} }
    interface Completion { void result(boolean success); }
    private final ReflowDocument document;
    private final Listener listener;
    private EpubDocument.Chapter chapter;
    private DocumentLocator locator;
    private Completion completion;
    private int generation;
    private boolean moving, userScrolling, dismissTouch, selected;
    private final GestureDetector taps;
    EpubPageView(Context context, ReflowDocument document, Listener listener) {
        super(context); this.document = document; this.listener = listener;
        taps=new GestureDetector(context,new GestureDetector.SimpleOnGestureListener(){@Override public boolean onSingleTapConfirmed(MotionEvent event){if(!selected&&event.getX()/Math.max(1,getWidth())>=.3f&&event.getX()/Math.max(1,getWidth())<.6f)performClick();return false;}});taps.setIsLongpressEnabled(false);
        getSettings().setJavaScriptEnabled(true);
        getSettings().setAllowFileAccess(false); getSettings().setAllowContentAccess(false);
        getSettings().setBlockNetworkLoads(true); getSettings().setDomStorageEnabled(false);getSettings().setSupportZoom(false);
        getSettings().setCacheMode(android.webkit.WebSettings.LOAD_NO_CACHE);
        setSaveEnabled(false); setContentDescription(document instanceof KindleDocument?"Kindle 正文":"EPUB 正文");
        addJavascriptInterface(new Bridge(), "XLibDocument");
        setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                try {
                    Uri url = request.getUrl();
                    if (!"https".equals(url.getScheme()) || !"book.xlib.invalid".equals(url.getHost())) return empty();
                    String path = url.getPath().substring(1);
                    if (!DocumentLocator.safeResource(path)) return empty();
                    return new WebResourceResponse(mime(path), "UTF-8", new ByteArrayInputStream(document.read(path)));
                } catch (Exception e) { return empty(); }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                listener.link(request.getUrl().toString()); return true;
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,String url){listener.link(url);return true;}
            @Override public void onPageFinished(WebView view, String url) {
                if (chapter == null) return;
                String script = "(function(){var request=Number(document.documentElement.getAttribute('data-xlib-generation'));if(!request)return;var nodes=[],walk=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode:function(n){return /^(SCRIPT|STYLE)$/.test(n.parentNode.tagName)?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT;}});var n;while(n=walk.nextNode())nodes.push(n);"
                        + "window.xlibNodes=nodes;window.xlibOffset=function(){var r=document.caretRangeFromPoint(12,20);if(!r)return -1;var sum=0;for(var i=0;i<nodes.length;i++){if(nodes[i]===r.startContainer)return sum+r.startOffset;sum+=nodes[i].length;}return -1;};"
                        + "window.xlibGo=function(offset){var sum=0;for(var i=0;i<nodes.length;i++){var n=nodes[i];if(sum+n.length>offset||i===nodes.length-1){n.parentElement.scrollIntoView({block:'start'});var r=document.createRange();r.setStart(n,Math.max(0,Math.min(n.length,offset-sum)));r.setEnd(n,Math.min(n.length,Math.max(0,offset-sum)+1));var b=r.getBoundingClientRect();window.scrollTo(0,window.scrollY+b.top-16);return;}sum+=n.length;}};"
                        + "window.xlibText=nodes.map(function(n){return n.data;}).join('');window.xlibPoint=function(container,offset){var sum=0,p=document.createRange();p.setStart(container,offset);p.collapse(true);for(var i=0;i<nodes.length;i++){if(nodes[i]===container)return sum+offset;if(p.comparePoint(nodes[i],nodes[i].length)<0)sum+=nodes[i].length;else break;}return sum;};document.addEventListener('selectionchange',function(){var s=window.getSelection();if(!s.rangeCount||s.isCollapsed){XLibDocument.selected('',request);return;}var r=s.getRangeAt(0),a=xlibPoint(r.startContainer,r.startOffset),b=xlibPoint(r.endContainer,r.endOffset);XLibDocument.selection(a,b,request);});"
                        + "XLibDocument.ready(nodes.map(function(n){return n.data;}).join('')," + "request);})();";
                evaluateJavascript(script, null);
            }
        });
    }
    private static WebResourceResponse empty() { return new WebResourceResponse("text/plain", "UTF-8", new ByteArrayInputStream(new byte[0])); }
    private static String mime(String path) {
        String lower=path.toLowerCase(Locale.ROOT);
        if(lower.endsWith(".css"))return "text/css"; if(lower.endsWith(".svg"))return "image/svg+xml";
        if(lower.endsWith(".png"))return "image/png"; if(lower.endsWith(".jpg")||lower.endsWith(".jpeg"))return "image/jpeg";
        if(lower.endsWith(".gif"))return "image/gif"; if(lower.endsWith(".woff2"))return "font/woff2";
        if(lower.endsWith(".woff"))return "font/woff"; if(lower.endsWith(".ttf"))return "font/ttf";
        return "application/octet-stream";
    }
    void show(DocumentLocator target, boolean dark, float fontSize, float lineSpacing, int fontFamily, Completion result) {
        if(completion!=null)completion.result(false);
        userScrolling=false;removeCallbacks(recordScroll);completion=result; locator=target; generation++; chapter=document.chapters.get(document.chapterIndex(target));
        String[] fonts={"sans-serif","serif","monospace","sans-serif","fangsong,serif"};
        String font=fonts[ReaderSettingsOptions.normalizeFontFamily(fontFamily)];
        String background=dark?"#101312":"#f6f7f4", color=dark?"#edf1ed":"#1c1f1d";
        String longChapterStyle=chapter.text.length()>262_144?"body>p{content-visibility:auto;contain-intrinsic-size:auto 100px}":"";
        String html="<!doctype html><html data-xlib-generation=\""+generation+"\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                + "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src https://book.xlib.invalid data:; style-src 'unsafe-inline' https://book.xlib.invalid; font-src https://book.xlib.invalid; script-src 'none'; connect-src 'none'; form-action 'none';\">"
                + "<style>html{background:"+background+"!important;color:"+color+"!important}body{padding:16px;overflow-wrap:anywhere;font-size:"+fontSize+"px!important;line-height:"+lineSpacing+"!important;font-family:"+font+"!important}html body p,html body div,html body span{font-size:inherit!important;line-height:inherit!important;font-family:inherit!important}body,p,div,span{color:inherit!important;background-color:transparent!important}img{max-width:100%;height:auto}a{color:"+(dark?"#89d8c5":"#0e473c")+"}"+longChapterStyle+"</style></head>"
                +chapter.html+"</html>";
        loadDataWithBaseURL("https://book.xlib.invalid/"+chapter.resource,html,"text/html","UTF-8",null);
    }
    void clearSelection() { evaluateJavascript("window.getSelection().removeAllRanges()", null); listener.selected(""); }
    private final class Bridge {
        @JavascriptInterface public void selection(int start,int end,int request){
            post(()->{if(request!=generation||chapter==null)return;int a=ReaderTextSelection.boundary(chapter.text,start),b=ReaderTextSelection.boundary(chapter.text,end);String text=b>=a?chapter.text.substring(a,b):"";if(document instanceof KindleDocument)text=text.replace("\ufffc", "");selected=!text.isEmpty();listener.selected(text);});
        }
        @JavascriptInterface public void selected(String text, int request) { post(() -> {if(request==generation){selected=!text.isEmpty();listener.selected(document instanceof KindleDocument?text.replace("\ufffc", ""):text);}}); }
        @JavascriptInterface public void ready(String text, int request) {
            post(() -> {
                if(request!=generation||completion==null)return;
                Completion callback=completion;completion=null;
                if(!chapter.text.equals(text)){callback.result(false);return;}
                evaluateJavascript("window.xlibGo("+document.localOffset(locator)+")",v -> callback.result(true));
            });
        }
    }
    void highlight(int start,int length) {
        evaluateJavascript("(function(){var nodes=window.xlibNodes;if(!nodes)return;var r=document.createRange(),sum=0,started=false;for(var i=0;i<nodes.length;i++){var n=nodes[i];if(!started&&sum+n.length>"+start+"){r.setStart(n,"+start+"-sum);started=true;}if(started&&sum+n.length>="+(start+length)+"){r.setEnd(n,"+(start+length)+"-sum);var s=window.getSelection();s.removeAllRanges();s.addRange(r);return;}sum+=n.length;}})()",null);
    }
    private final Runnable recordScroll=this::recordCurrentScroll;
    private void recordCurrentScroll() {
        final int request=generation;
        if(!userScrolling||completion!=null)return;
        evaluateJavascript("window.xlibOffset && window.getSelection().isCollapsed ? window.xlibOffset() : -1", value -> {
            try { int offset=Integer.parseInt(value);if(request==generation&&offset>=0)listener.moved(offset); } catch(Exception ignored) { }
        });
    }
    @Override protected void onScrollChanged(int x,int y,int oldX,int oldY){
        super.onScrollChanged(x,y,oldX,oldY);
        if(userScrolling){removeCallbacks(recordScroll);postDelayed(recordScroll,300);}
    }
    @Override public boolean onTouchEvent(MotionEvent event) {
        if(event.getActionMasked()==MotionEvent.ACTION_DOWN){dismissTouch=listener.dismissMenus();moving=false;userScrolling=false;}
        if(dismissTouch){if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL)dismissTouch=false;return true;}
        taps.onTouchEvent(event);
        if(event.getActionMasked()==MotionEvent.ACTION_MOVE){moving=true;userScrolling=true;}
        boolean handled=super.onTouchEvent(event);
        if(event.getActionMasked()==MotionEvent.ACTION_UP&&moving){
            removeCallbacks(recordScroll);recordCurrentScroll();postDelayed(recordScroll,300);
        }else if(event.getActionMasked()==MotionEvent.ACTION_CANCEL){moving=false;userScrolling=false;removeCallbacks(recordScroll);}
        return handled;
    }
    @Override public boolean performClick() {
        super.performClick();
        if(!selected)listener.tapped();
        return true;
    }
    // Keep WebView's native selection handles, with the same app-owned actions as TXT.
    @Override public ActionMode startActionMode(ActionMode.Callback callback,int type){return super.startActionMode(new ActionMode.Callback2(){
        @Override public boolean onCreateActionMode(ActionMode mode,Menu menu){boolean created=callback.onCreateActionMode(mode,menu);menu.clear();return created;}
        @Override public boolean onPrepareActionMode(ActionMode mode,Menu menu){callback.onPrepareActionMode(mode,menu);menu.clear();return true;}
        @Override public boolean onActionItemClicked(ActionMode mode,MenuItem item){return false;}
        @Override public void onDestroyActionMode(ActionMode mode){callback.onDestroyActionMode(mode);}
        @Override public void onGetContentRect(ActionMode mode,android.view.View view,Rect rect){if(callback instanceof ActionMode.Callback2)((ActionMode.Callback2)callback).onGetContentRect(mode,view,rect);else super.onGetContentRect(mode,view,rect);}
    },type);}
    void release() { generation++;completion=null;removeCallbacks(recordScroll);stopLoading();removeJavascriptInterface("XLibDocument");destroy(); }
}
