package com.xlib.txtreader;

import android.app.Activity;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Shared image reader for formal CBZ/CBR books and isolated one-shot CBZ previews. */
public final class ComicPreviewActivity extends Activity {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    private final LinkedHashMap<Integer,Bitmap> cache=new LinkedHashMap<>(4,.75f,true);
    private final List<ImageButton> icons=new ArrayList<>();
    private final List<Button> buttons=new ArrayList<>();
    private volatile boolean destroyed;
    private volatile int generation;
    private ComicDocument document;
    private volatile File directory,source;
    private volatile boolean sourceComplete;
    private ComicPageView pageView;
    private ReaderChrome chrome;
    private LinearLayout top,bottom,seekPanel;
    private TextView status,percentage;
    private Button progress,fit;
    private SeekBar seek;
    private ImageButton theme;
    private int page=-1,count;
    private boolean dark,menus,ready,rtl,tracking;
    private LocalDatabase database;
    private Book book;
    private String sourceHash;
    private DocumentLocator formal,position;
    private long readAt;
    private boolean resumed,temporary,opening=true;
    private DocumentSyncSession sync;
    private ImageButton bookmarkButton;
    private Button returnToReading;
    private interface NavigationResult {void completed(boolean success);}


    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        try {
            database=LocalDatabase.open(this,getSharedPreferences("xlib_reader",MODE_PRIVATE));
            ReadingPreferences preferences=new ReadingPreferences(database);
            dark=preferences.appTheme()==ReaderSettingsOptions.THEME_DARK;
            rtl=preferences.comicRightToLeft();
            long bookId=getIntent().getLongExtra("bookId",-1);
            if(bookId>=0){for(Book candidate:database.loadBooks())if(candidate.id==bookId)book=candidate;
                if(book==null||book.locatorUnavailable||!("cbz".equals(book.format)||"cbr".equals(book.format)))throw new IOException("此书或定位暂不可读取，已有数据保留");
                source=new File(book.path);formal=position=book.locator;readAt=book.updatedAt;
            }
            buildUi();
            int initial=saved==null?0:saved.getInt("page",0);double y=saved==null?0:saved.getDouble("y",0);
            if(saved!=null){String path=saved.getString("source");if(book==null&&path!=null)source=new File(path);pageView.fitWidth(saved.getBoolean("fitWidth",true));}
            status.setText("正在准备漫画…");
            worker.execute(()->open(initial,y));
        } catch(Exception error){failure("无法准备漫画，请返回书架重试");}
    }
    private void buildUi() {
        chrome=new ReaderChrome(this,dark?UiKit.DARK_BACKGROUND:UiKit.LIGHT_BACKGROUND);
        chrome.setOnApplyWindowInsetsListener((view,insets)->{view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        pageView=new ComicPageView(this,new ComicPageView.Listener(){
            public void tap(float fraction){if(fraction>=.30f&&fraction<.60f)menus(true);else step((fraction<.30f?-1:1)*(rtl?-1:1));}
            public void turn(int direction){step(direction*(rtl?-1:1));}
            public void moved(double y){if(book!=null&&ready&&!opening&&resumed&&!temporary&&(sync==null||sync.canRead())){DocumentLocator target=document.manifest.locator(book.format,page,y);if(commit(target,null)){position=target;updateStatus();}}}
            public boolean dismissMenus(){if(!menus)return false;menus(false);return true;}
        });
        FrameLayout.LayoutParams body=new FrameLayout.LayoutParams(-1,-1);body.topMargin=dp(7);body.bottomMargin=dp(26);chrome.addView(pageView,body);
        status=text(11);status.setGravity(Gravity.CENTER);chrome.addView(status,new FrameLayout.LayoutParams(-1,dp(24),Gravity.BOTTOM));
        top=ReaderChrome.menu(this,dark,true);
        LinearLayout zoom=new LinearLayout(this);zoom.addView(button("−","缩小漫画",()->pageView.zoomBy(.8f)),new LinearLayout.LayoutParams(dp(48),dp(48)));zoom.addView(button("+","放大漫画",()->pageView.zoomBy(1.25f)),new LinearLayout.LayoutParams(dp(48),dp(48)));top.addView(zoom,new LinearLayout.LayoutParams(0,dp(48),1));
        ReaderChrome.enabled(icon(top,R.drawable.ic_search,"搜索",()->{}),false);
        theme=icon(top,dark?R.drawable.ic_sun:R.drawable.ic_moon,"切换阅读主题",()->{dark=!dark;new ReadingPreferences(database).setAppTheme(dark?ReaderSettingsOptions.THEME_DARK:ReaderSettingsOptions.THEME_LIGHT);applyTheme();});
        icon(top,R.drawable.ic_screen_lock,"保持屏幕常亮",()->{ReadingPreferences p=new ReadingPreferences(database);p.setReadingKeepScreenOn(!p.readingKeepScreenOn());keepAwake();});
        icon(top,R.drawable.ic_settings,"漫画阅读设置",this::settings);
        FrameLayout.LayoutParams topLayout=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);topLayout.setMargins(dp(12),dp(8),dp(12),0);chrome.addView(top,topLayout);
        bottom=ReaderChrome.menu(this,dark,false);
        seekPanel=new LinearLayout(this);seekPanel.setGravity(Gravity.CENTER_VERTICAL);seekPanel.setVisibility(View.GONE);
        percentage=text(13);percentage.setGravity(Gravity.CENTER);seekPanel.addView(percentage,new LinearLayout.LayoutParams(dp(58),dp(48)));
        seek=new SeekBar(this);seek.setContentDescription("阅读进度");seekPanel.addView(seek,new LinearLayout.LayoutParams(0,dp(48),1));bottom.addView(seekPanel);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar bar,int value,boolean user){if(count>0)percentage.setText(percent(value));}
            public void onStartTrackingTouch(SeekBar bar){tracking=true;}
            public void onStopTrackingTouch(SeekBar bar){tracking=false;navigate(bar.getProgress(),0);}
        });
        LinearLayout nav=new AdaptiveRow(this);nav.setGravity(Gravity.CENTER_VERTICAL);
        icon(nav,R.drawable.ic_toc,"跳页",this::jump);
        bookmarkButton=icon(nav,R.drawable.ic_bookmark,"书签",this::bookmarks);ReaderChrome.enabled(bookmarkButton,book!=null);
        icon(nav,R.drawable.ic_progress_back,"上一页",()->step(-1));
        progress=button("","调整阅读进度",()->{if(ready)seekPanel.setVisibility(seekPanel.getVisibility()==View.VISIBLE?View.GONE:View.VISIBLE);});progress.setTextSize(11);nav.addView(progress,new LinearLayout.LayoutParams(0,dp(48),1));
        icon(nav,R.drawable.ic_progress_forward,"下一页",()->step(1));
        icon(nav,R.drawable.ic_more,"阅读设置",this::settings);bottom.addView(nav);
        fit=button("适宽","切换适宽或整页",()->{pageView.fitWidth(!pageView.fitWidth());fit.setText(pageView.fitWidth()?"适宽":"整页");});
        // Format-specific fitting uses the same menu/button styles as TXT.
        bottom.addView(fit,new LinearLayout.LayoutParams(-1,dp(48)));
        returnToReading=button("返回正式阅读","返回正式阅读",()->{if(book==null||formal==null)return;DocumentLocator target=formal;navigate(target.page,target.y,false,null,success->{if(success){temporary=false;if(sync!=null)sync.temporary(false);returnToReading.setVisibility(View.GONE);}});});returnToReading.setVisibility(View.GONE);bottom.addView(returnToReading);
        FrameLayout.LayoutParams bottomLayout=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);bottomLayout.setMargins(dp(12),0,dp(12),dp(26));chrome.addView(bottom,bottomLayout);
        setContentView(chrome);applyTheme();
    }
    private void open(int initial,double y) {
        try {
            File root=new File(getCacheDir(),"comic-previews");if(!root.exists()&&!root.mkdirs())throw new IOException("无法创建漫画预览缓存");
            if(book!=null){
                if(!source.isFile())throw new IOException("原漫画文件缺失，书签与阅读位置已保留");
                directory=File.createTempFile("reader-","",root);if(!directory.delete()||!directory.mkdir())throw new IOException("无法创建阅读缓存");
                sourceComplete=true;
                sourceHash=new BookHashCache(database).resolve(book.id,source,()->destroyed).bookHash;
                ComicArchive.check(()->destroyed);
                String previous=database.documentHash(book.id);if(previous!=null&&!previous.equals(sourceHash))throw new IOException("原文件已改变，旧位置保留，请重新导入");
            }else if(source==null) {
                cleanOld(root);directory=File.createTempFile("session-","",root);if(!directory.delete()||!directory.mkdir())throw new IOException("无法准备漫画预览");source=new File(directory,"source.cbz");
                copySource();
                sourceComplete=true;
            } else {
                directory=source.getCanonicalFile().getParentFile();
                if(directory==null||!root.getCanonicalFile().equals(directory.getParentFile())||!source.getName().equals("source.cbz"))throw new IOException("漫画预览已失效，请重新选择文件");
                sourceComplete=source.isFile();
            }
            ComicArchive.check(()->destroyed);
            String name=getIntent().getStringExtra("sourceName");
            String detected=DocumentFormats.detect(source,book==null?(name==null?"book.cbz":name):book.sourceName,()->destroyed);
            if(book==null?!"cbz".equals(detected):!book.format.equals(detected))throw new IOException("请选择支持的漫画文件");
            ComicDocument opened=new ComicDocument(source,directory,()->destroyed);document=opened;
            opened.validate(()->destroyed);
            ComicArchive.check(()->destroyed);
            main.post(()->{if(destroyed)return;count=opened.pageCount;seek.setMax(count-1);ready=true;fit.setText(pageView.fitWidth()?"适宽":"整页");
                if(book!=null){if(formal!=null&&!opened.manifest.valid(formal,book.format)){failure("保存的位置与原包清单不匹配，已有数据保留");return;}
                    if(formal==null){formal=opened.manifest.locator(book.format,0,0);position=formal;try{database.saveDocumentPosition(book,formal,sourceHash,readAt);}catch(Exception error){failure("无法保存本地位置，已有数据保留");return;}}
                }
                DocumentLocator target=formal;
                navigate(book==null?Math.max(0,Math.min(count-1,initial)):target.page,book==null?y:target.y,false,null,success->{if(!success)return;opening=false;if(book!=null){prepareSync();if(resumed)sync.resume();}});
            });
        }catch(Exception error){main.post(()->{if(!destroyed)failure(error instanceof IOException?error.getMessage():"漫画包损坏或无法读取");});}
    }
    private void copySource()throws IOException {
        if(getIntent().getData()==null)throw new IOException("未选择漫画文件");
        try(InputStream input=getContentResolver().openInputStream(getIntent().getData());FileOutputStream output=new FileOutputStream(source)){
            if(input==null)throw new IOException("无法读取选中的漫画包");
            byte[] buffer=new byte[65536];int read;long bytes=0,checkAt=0;
            while((read=input.read(buffer))!=-1){ComicArchive.check(()->destroyed);bytes+=read;if(bytes>ComicArchive.MAX_SOURCE)throw new IOException("漫画包超过 1 GiB");if(bytes>=checkAt){ComicPreviewFiles.reserve(directory,Math.min(1024*1024,ComicArchive.MAX_SOURCE-bytes+read));checkAt=bytes+1024*1024;}output.write(buffer,0,read);}
            output.flush();
        }catch(IOException error){source.delete();throw error;}
    }
    private void step(int direction){if(ready&&page>=0)navigate(page+direction,0);}
    private void navigate(int target,double y) {navigate(target,y,true,null,success->{});}
    private void navigate(int target,double y,boolean user,Long preservedTime,NavigationResult completion) {
        if(!ready||target<0||target>=count||destroyed||(user&&opening)||(user&&!temporary&&sync!=null&&!sync.canRead())){completion.completed(false);return;}
        int request=++generation;Bitmap cached=cache.get(target);
        if(cached!=null){display(target,cached,y,user,preservedTime,completion);return;}
        status.setText("正在准备第 "+(target+1)+" 页…");int width=Math.max(pageView.getWidth(),getResources().getDisplayMetrics().widthPixels);
        worker.execute(()->{try{
            if(destroyed||request!=generation)return;
            Bitmap image=document.page(target,width,()->destroyed||request!=generation);
            main.post(()->{if(destroyed||request!=generation){image.recycle();return;}cache.put(target,image);display(target,image,y,user,preservedTime,completion);});
        }catch(Exception error){main.post(()->{if(!destroyed&&request==generation){updateStatus();message("页面准备失败，原位置保留，请重试");completion.completed(false);}});}});
    }
    private void display(int target,Bitmap image,double y,boolean user,Long preservedTime,NavigationResult completion){
        if(book!=null&&(user||preservedTime!=null)&&!resumed){completion.completed(false);return;}
        DocumentLocator next=book==null?null:document.manifest.locator(book.format,target,y);
        if(book!=null&&(preservedTime!=null||(user&&!temporary))&&!commit(next,preservedTime)){completion.completed(false);return;}
        page=target;position=next;pageView.page(image,y);trim(false);updateStatus();completion.completed(true);
    }
    private boolean commit(DocumentLocator next,Long preservedTime){
        if(preservedTime==null&&next.equals(formal))return true;
        long time=preservedTime==null?SyncRules.monotonicReadAt(System.currentTimeMillis(),readAt):preservedTime;
        try{database.saveDocumentPosition(book,next,sourceHash,time);}catch(Exception failure){message("阅读位置保存失败，请检查存储空间；已有位置保留");return false;}
        formal=next;readAt=time;if(sync!=null&&preservedTime==null)sync.moved();return true;
    }
    private void prepareSync(){
        sync=new DocumentSyncSession(this,database,book,sourceHash,new DocumentSyncSession.Listener(){
            public void state(String text){} // Sync details remain in its explicit menu, outside the reading canvas.
            public void remote(DocumentLocator target,long time,Runnable accepted,Runnable rejected){
                if(!document.manifest.valid(target,book.format)){rejected.run();message("远端位置与当前原包不匹配，已保留本地位置");return;}
                AppDialogs.builder(ComicPreviewActivity.this,dark).setTitle("发现更新的阅读进度")
                    .setMessage(String.format(Locale.getDefault(),"本机 %.1f%% · 远端 %.1f%%",formal.progress()*100,target.progress()*100))
                    .setPositiveButton("跳转",(d,w)->navigate(target.page,target.y,false,time,success->{if(success)accepted.run();else rejected.run();}))
                    .setNegativeButton("暂不跳转",(d,w)->rejected.run()).setOnCancelListener(d->rejected.run()).show();
            }
        });sync.validateWith(value->document.manifest.valid(value,book.format));
    }
    private void bookmarks(){
        if(book==null||!ready||opening||position==null)return;
        java.util.List<LocalDatabase.DocumentBookmark> saved;
        try{saved=database.documentBookmarks(book.id);}catch(Exception error){message("书签位置暂不支持，已有数据保留");return;}
        LinearLayout list=new LinearLayout(this);list.setOrientation(LinearLayout.VERTICAL);
        android.app.AlertDialog dialog=AppDialogs.builder(this,dark).setTitle("本地书签").setView(AppDialogs.viewport(this,list)).setNegativeButton("关闭",null).create();
        Button add=dialogButton("添加当前位置","添加当前位置",()->{if(temporary)return;try{boolean added=database.addDocumentBookmark(book.id,position);dialog.dismiss();message(added?"已添加书签":"当前位置已有书签");}catch(Exception e){message("书签保存失败，已有数据保留");}});ReaderChrome.enabled(add,!temporary);list.addView(add);
        for(LocalDatabase.DocumentBookmark mark:saved){
            Button row=dialogButton("第 "+(mark.locator.page+1)+" 页 · "+String.format(Locale.getDefault(),"%.1f%%",mark.locator.progress()*100),"打开书签 "+(mark.locator.page+1),()->{
                dialog.dismiss();if(!document.manifest.valid(mark.locator,book.format)){message("书签与原包清单不匹配，已有数据保留");return;}
                temporary=true;if(sync!=null)sync.temporary(true);returnToReading.setVisibility(View.VISIBLE);navigate(mark.locator.page,mark.locator.y,false,null,success->{});
            });list.addView(row);
            Button remove=dialogButton("删除书签","删除书签 "+(mark.locator.page+1),()->AppDialogs.builder(this,dark).setTitle("删除此书签？").setNegativeButton("取消",null).setPositiveButton("删除",(d,w)->{database.deleteDocumentBookmark(book.id,mark.id);dialog.dismiss();bookmarks();}).show());list.addView(remove);
        }
        dialog.show();
    }
    private void syncDetails(){if(sync==null)return;AppDialogs.builder(this,dark).setTitle("阅读进度同步").setMessage(sync.message()).setPositiveButton("刷新",(d,w)->sync.refresh()).setNegativeButton("关闭",null).setNeutralButton("删除本书云端进度",(d,w)->AppDialogs.builder(this,dark).setTitle("删除本书云端进度？").setMessage("本地书籍和书签保留，成功后本次阅读暂停上传。").setNegativeButton("取消",null).setPositiveButton("删除",(confirm,which)->sync.delete()).show()).show();}

    private void updateStatus(){if(page<0)return;String value=String.format(Locale.getDefault(),"第 %d / %d 页 · %s",page+1,count,percent(page));status.setText(value);progress.setText(String.format(Locale.getDefault(),"%d / %d\n%s",page+1,count,percent(page)));if(!tracking){seek.setProgress(page);percentage.setText(percent(page));}}
    private String percent(int index){return String.format(Locale.getDefault(),"%.1f%%",(index+1)*100d/Math.max(1,count));}
    private void jump(){if(ready)ReaderDialogs.jump(this,dark,page,count,target->navigate(target,0));}
    private void settings(){ReaderDialogs.choose(this,dark,"漫画阅读",book==null?new String[]{pageView.fitWidth()?"整页显示":"适宽显示",rtl?"阅读方向：从右向左":"阅读方向：从左向右","开源许可","返回书架"}:new String[]{pageView.fitWidth()?"整页显示":"适宽显示",rtl?"阅读方向：从右向左":"阅读方向：从左向右","同步","开源许可","返回书架"},i->{if(i==0){pageView.fitWidth(!pageView.fitWidth());fit.setText(pageView.fitWidth()?"适宽":"整页");}else if(i==1){rtl=!rtl;new ReadingPreferences(database).setComicRightToLeft(rtl);}else if(i==2&&book!=null)syncDetails();else if(i==(book==null?2:3))licenses();else finish();});}
    private void licenses(){
        StringBuilder text=new StringBuilder();
        try{for(String name:new String[]{"UnRAR-LICENSE.txt","UnRAR-ACKNOWLEDGMENTS.txt","libarchive-COPYING.txt"})try(InputStream input=getAssets().open(name)){java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();byte[] data=new byte[4096];int n;while((n=input.read(data))!=-1)bytes.write(data,0,n);text.append(name).append("\n\n").append(bytes.toString("UTF-8")).append("\n\n");}}
        catch(IOException error){message("无法读取开源许可");return;}
        TextView content=text(13);content.setText(text.toString());content.setTextColor(dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT);content.setPadding(dp(24),dp(12),dp(24),dp(12));
        AppDialogs.builder(this,dark).setTitle("开源许可").setView(AppDialogs.viewport(this,content)).setPositiveButton("关闭",null).show();
    }
    private Button dialogButton(String label,String description,Runnable action){Button view=button(label,description,action);buttons.remove(view);UiKit.styleButton(this,view,dark?UiKit.DARK_SURFACE_VARIANT:UiKit.LIGHT_SURFACE_VARIANT,dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT,14);return view;}
    private void message(String value){ReaderDialogs.message(this,dark,book==null?"漫画预览":"漫画阅读",value,null);}
    private void failure(String message){ready=false;if(status!=null)status.setText("漫画无法打开");ReaderDialogs.message(this,dark,"无法打开漫画",message==null?"漫画包损坏或无法读取":message,this::finish);}
    private void menus(boolean visible){menus=visible;top.setVisibility(visible?View.VISIBLE:View.GONE);bottom.setVisibility(visible?View.VISIBLE:View.GONE);if(!visible)seekPanel.setVisibility(View.GONE);}
    private TextView text(int size){TextView view=new TextView(this);view.setTextSize(size);return view;}
    private Button button(String label,String description,Runnable action){Button view=new Button(this);view.setText(label);view.setContentDescription(description);view.setTextSize(13);view.setMinWidth(0);view.setMinimumWidth(0);view.setOnClickListener(v->action.run());buttons.add(view);return view;}
    private ImageButton icon(LinearLayout parent,int resource,String label,Runnable action){ImageButton view=ReaderChrome.icon(this,dark,resource,label,action);icons.add(view);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(48),dp(48));lp.leftMargin=dp(4);parent.addView(view,lp);return view;}
    private void applyTheme(){int bg=dark?UiKit.DARK_BACKGROUND:UiKit.LIGHT_BACKGROUND,fg=dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT,surface=dark?UiKit.DARK_SURFACE:UiKit.LIGHT_SURFACE;chrome.setBackgroundColor(bg);pageView.background(bg);top.setBackground(UiKit.rounded(this,surface,22));bottom.setBackground(UiKit.rounded(this,surface,24));for(ImageButton view:icons)UiKit.styleIconButton(this,view,fg,dark?UiKit.DARK_SURFACE_VARIANT:UiKit.LIGHT_SURFACE_VARIANT,14);for(Button view:buttons)UiKit.styleButton(this,view,dark?UiKit.DARK_SURFACE_VARIANT:UiKit.LIGHT_SURFACE_VARIANT,fg,14);for(TextView view:new TextView[]{status,percentage})view.setTextColor(fg);UiKit.styleReaderSeekBar(this,seek,dark);theme.setImageResource(dark?R.drawable.ic_sun:R.drawable.ic_moon);getWindow().setStatusBarColor(bg);getWindow().setNavigationBarColor(bg);getWindow().getDecorView().setSystemUiVisibility(dark?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);}
    private void keepAwake(){if(database!=null&&new ReadingPreferences(database).readingKeepScreenOn())getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);else getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);}
    private int dp(int value){return UiKit.dp(this,value);}
    private void trim(boolean all){long bytes=0;for(Bitmap image:cache.values())bytes+=image.getAllocationByteCount();java.util.Iterator<java.util.Map.Entry<Integer,Bitmap>> iterator=cache.entrySet().iterator();while(iterator.hasNext()){java.util.Map.Entry<Integer,Bitmap> entry=iterator.next();if(entry.getKey()==page)continue;if(all||bytes>ComicDocument.CACHE_BYTES||cache.size()>3){bytes-=entry.getValue().getAllocationByteCount();entry.getValue().recycle();iterator.remove();}}}
    @Override public void onTrimMemory(int level){super.onTrimMemory(level);trim(true);}
    @Override protected void onResume(){super.onResume();resumed=true;keepAwake();if(sync!=null)sync.resume();}
    @Override protected void onPause(){super.onPause();resumed=false;if(sync!=null)sync.pause();getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);}
    @Override protected void onSaveInstanceState(Bundle saved){super.onSaveInstanceState(saved);if(book==null&&sourceComplete&&source!=null&&source.isFile())saved.putString("source",source.getAbsolutePath());saved.putInt("page",Math.max(0,page));saved.putDouble("y",pageView==null?0:pageView.anchor());saved.putBoolean("fitWidth",pageView==null||pageView.fitWidth());}
    @Override public void onBackPressed(){if(menus){menus(false);return;}if(temporary&&formal!=null){returnToReading.performClick();return;}super.onBackPressed();}
    @Override protected void onDestroy(){destroyed=true;if(sync!=null)sync.close();++generation;if(pageView!=null)pageView.release();for(Bitmap image:cache.values())image.recycle();cache.clear();boolean remove=book!=null||isFinishing()||!sourceComplete;worker.execute(()->{try{if(document!=null)document.close();}catch(IOException ignored){}finally{if(remove&&directory!=null)delete(directory);if(database!=null)database.close();}});worker.shutdown();super.onDestroy();}
    private static void cleanOld(File root){File[] children=root.listFiles();if(children!=null)for(File child:children)if(System.currentTimeMillis()-child.lastModified()>24L*60*60*1000)delete(child);}
    private static void delete(File path){File[] children=path.listFiles();if(children!=null)for(File child:children)delete(child);path.delete();}
}
