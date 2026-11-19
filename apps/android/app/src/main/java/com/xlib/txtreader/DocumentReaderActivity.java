package com.xlib.txtreader;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.ImageButton;
import android.widget.SeekBar;
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Format reader with a separate opening/temporary/formal position lifecycle. */
public final class DocumentReaderActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private LocalDatabase database;
    private Book book;
    private PdfDocument pdf;
    private ReflowDocument epub;
    private EpubPageView epubView;
    private String epubSelection = "";
    private String sourceHash;
    private DocumentLocator position, formal;
    private long readAt;
    private boolean temporary, ready, resumed, opening;
    private volatile boolean destroyed;
    private volatile int generation;
    private PdfPageView pdfView;
    private TextView status;
    private Button copy, cancel, returnToReading;
    private FrameLayout content;
    private boolean dark;
    private DocumentSearch search;
    private DocumentSearch.Source activeSearchSource;
    private boolean searching;
    private AlertDialog searchDialog;
    private String lastSearchQuery = "";
    private DocumentSearch.Hit selectedSearchHit;
    private final List<DocumentSearch.Hit> searchHits = new ArrayList<>();
    private DocumentSyncSession sync;
    private AlertDialog remoteDialog;
    private ReaderChrome readerChrome;
    private LinearLayout readerTopBar, readerBottomBar, seekPanel, selectionBar;
    private Button progressButton;
    private TextView seekPercentage;
    private SeekBar seekBar;
    private boolean readerMenusOpen, seekTracking;
    private final List<ImageButton> readerIcons = new ArrayList<>();
    private ImageButton themeButton, keepAwakeButton;
    private View searchButton;
    private boolean epubSearchAvailable;
    private boolean pdfSearchAvailable, textProbePending;
    private int nextTextProbe;
    private int displayedPdfPage=-1;

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        try {
            database = LocalDatabase.open(this, getSharedPreferences("xlib_reader", MODE_PRIVATE));
            long id = getIntent().getLongExtra("bookId", -1);
            for (Book candidate : database.loadBooks()) if (candidate.id == id) book = candidate;
            if (book == null || (!"pdf".equals(book.format)&&!"epub".equals(book.format)&&!"kindle".equals(book.format))) throw new IllegalArgumentException("文档格式不支持");
            if(book.locatorUnavailable)throw new IllegalStateException("定位版本不支持，原位置保留");
            formal = position = book.locator; readAt = book.updatedAt;
            dark = new ReadingPreferences(database).appTheme() == ReaderSettingsOptions.THEME_DARK;
            buildUi(); if (isEpub()) openEpub(); else if("pdf".equals(book.format))openPdf(null, false);
        } catch (Exception error) { error("无法打开文档，请返回书架重试", true); }
    }

    private void buildUi() { buildPdfUi(); }

    /** Same surface, floating cards, icons and progress control as the TXT reader. */
    private void buildPdfUi() {
        readerChrome = new ReaderChrome(this, dark ? UiKit.DARK_BACKGROUND : UiKit.LIGHT_BACKGROUND);
        readerChrome.setOnApplyWindowInsetsListener((view,insets)->{view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        content = new FrameLayout(this);
        pdfView = new PdfPageView(this, new PdfPageView.Listener() {
            public void selectionChanged(boolean selected) {
                if(copy==null)return;
                copy.setVisibility(selected?View.VISIBLE:View.GONE); cancel.setVisibility(selected?View.VISIBLE:View.GONE);
                selectionBar.setVisibility(selected||temporary?View.VISIBLE:View.GONE);
                if(selected)setReaderMenus(false);
            }
            public void panned(double y) {
                if(resumed&&position!=null&&!temporary&&ready&&!opening&&(sync==null||sync.canRead())) {
                    position=DocumentLocator.pdf(position.page,position.pageCount,y);commit(position,null);updateStatus();
                }
            }
            public void tapped(float fraction) {
                if(!ready||opening)return;
                if(fraction>=.30f&&fraction<.60f)setReaderMenus(true);else step(fraction<.30f?-1:1);
            }
            public void turned(int direction) { step(direction); }
            public boolean dismissMenus() { if(!readerMenusOpen)return false;setReaderMenus(false);return true; }
        });
        pdfView.background(dark ? UiKit.DARK_BACKGROUND : UiKit.LIGHT_BACKGROUND);
        content.addView(pdfView,new FrameLayout.LayoutParams(-1,-1));
        FrameLayout.LayoutParams body=new FrameLayout.LayoutParams(-1,-1);body.topMargin=dp(7);body.bottomMargin=dp(26);
        readerChrome.addView(content,body);
        status=new TextView(this);status.setGravity(Gravity.CENTER);status.setTextSize(11);status.setSingleLine(true);
        FrameLayout.LayoutParams footer=new FrameLayout.LayoutParams(-1,dp(24),Gravity.BOTTOM);readerChrome.addView(status,footer);
        readerTopBar=ReaderChrome.menu(this,dark,true);
        LinearLayout zoom=row();
        Button smaller=button(isEpub()?"A−":"−",()->resizeContent(-1));smaller.setContentDescription(isEpub()?"减小字号":"缩小 PDF");
        Button larger=button(isEpub()?"A+":"+",()->resizeContent(1));larger.setContentDescription(isEpub()?"增大字号":"放大 PDF");
        zoom.addView(smaller,new LinearLayout.LayoutParams(dp(48),dp(48)));zoom.addView(larger,new LinearLayout.LayoutParams(dp(48),dp(48)));
        readerTopBar.addView(zoom,new LinearLayout.LayoutParams(0,dp(48),1));
        searchButton=addReaderIcon(readerTopBar,R.drawable.ic_search,"搜索",this::showSearch);
        ReaderChrome.enabled(searchButton,false);
        themeButton=addReaderIcon(readerTopBar,dark?R.drawable.ic_sun:R.drawable.ic_moon,"切换阅读主题",()->{
            dark=!dark;new ReadingPreferences(database).setAppTheme(dark?ReaderSettingsOptions.THEME_DARK:ReaderSettingsOptions.THEME_LIGHT);applyPdfTheme();if(epub!=null)navigate(position,false);
        });
        keepAwakeButton=addReaderIcon(readerTopBar,R.drawable.ic_screen_lock,"保持屏幕常亮",()->{
            ReadingPreferences p=new ReadingPreferences(database);p.setReadingKeepScreenOn(!p.readingKeepScreenOn());applyKeepAwake();
        });
        addReaderIcon(readerTopBar,R.drawable.ic_settings,isEpub()?"排版":"PDF 裁边",()->{if(isEpub())preferences();else showPdfCrop();});
        FrameLayout.LayoutParams top=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);top.setMargins(dp(12),dp(8),dp(12),0);readerChrome.addView(readerTopBar,top);
        readerBottomBar=ReaderChrome.menu(this,dark,false);
        seekPanel=new LinearLayout(this);seekPanel.setGravity(Gravity.CENTER_VERTICAL);seekPanel.setVisibility(View.GONE);
        seekPercentage=new TextView(this);seekPercentage.setTextSize(13);seekPanel.addView(seekPercentage,new LinearLayout.LayoutParams(dp(58),dp(48)));
        seekBar=new SeekBar(this);seekBar.setContentDescription("阅读进度");UiKit.styleReaderSeekBar(this,seekBar,dark);
        seekBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar bar,int value,boolean user){
                if(position==null||(isEpub()&&epub==null))return;double progress=epub instanceof KindleDocument?value/(double)((KindleDocument)epub).canonicalText.length():value/(double)(isEpub()?epub.chapters.size():position.pageCount);
                seekPercentage.setText(String.format(Locale.getDefault(),"%.1f%%",progress*100));
            }
            public void onStartTrackingTouch(SeekBar bar){seekTracking=true;}
            public void onStopTrackingTouch(SeekBar bar){seekTracking=false;if(epub instanceof KindleDocument)navigate(((KindleDocument)epub).atOffset(bar.getProgress()),true);else if(epub!=null)navigate(epub.locator(bar.getProgress(),0),true);else if(pdf!=null)navigate(DocumentLocator.pdf(bar.getProgress(),pdf.pageCount,0),true);}
        });
        seekPanel.addView(seekBar,new LinearLayout.LayoutParams(0,dp(48),1));readerBottomBar.addView(seekPanel);
        LinearLayout nav=new AdaptiveRow(this);addReaderIcon(nav,R.drawable.ic_toc,isEpub()?"目录":"跳页",()->{if(isEpub())showToc();else jump();});addReaderIcon(nav,R.drawable.ic_bookmark,"书签",this::showBookmarks);
        addReaderIcon(nav,R.drawable.ic_progress_back,isEpub()?"上一章":"上一页",()->step(-1));
        progressButton=button("",()->seekPanel.setVisibility(seekPanel.getVisibility()==View.VISIBLE?View.GONE:View.VISIBLE));progressButton.setContentDescription("调整阅读进度");progressButton.setTextSize(11);
        progressButton.setOnLongClickListener(v->{jump();return true;});nav.addView(progressButton,new LinearLayout.LayoutParams(0,dp(48),1));
        addReaderIcon(nav,R.drawable.ic_progress_forward,isEpub()?"下一章":"下一页",()->step(1));
        addReaderIcon(nav,R.drawable.ic_more,"阅读设置",()->AppDialogs.builder(this,dark).setTitle(book.title)
                .setItems(new String[]{isEpub()?"排版":"PDF 裁边",isEpub()?"跳章":"跳页","书签","同步","返回书架"},(d,i)->{if(i==0){if(isEpub())preferences();else showPdfCrop();}else if(i==1)jump();else if(i==2)showBookmarks();else if(i==3)showSync();else finish();}).show());
        readerBottomBar.addView(nav);
        FrameLayout.LayoutParams bottom=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);bottom.setMargins(dp(12),0,dp(12),dp(26));readerChrome.addView(readerBottomBar,bottom);
        selectionBar=ReaderChrome.menu(this,dark,true);
        copy=button("复制",()->{String value=epub==null?pdfView.selectedText():epubSelection;if(!value.isEmpty()){((ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("",value));clearSelection();}});
        cancel=button("取消选文",this::clearSelection);copy.setVisibility(View.GONE);cancel.setVisibility(View.GONE);
        returnToReading=button("返回正式阅读",()->{temporary=false;if(sync!=null)sync.temporary(false);returnToReading.setVisibility(View.GONE);selectionBar.setVisibility(View.GONE);navigate(formal,false);});returnToReading.setVisibility(View.GONE);
        selectionBar.addView(copy);selectionBar.addView(cancel);selectionBar.addView(returnToReading);
        FrameLayout.LayoutParams selected=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);selected.topMargin=dp(76);readerChrome.addView(selectionBar,selected);
        setContentView(readerChrome);applyPdfTheme();applyKeepAwake();
    }
    private boolean isEpub(){return "epub".equals(book.format)||"kindle".equals(book.format);}
    private void resizeContent(int direction){
        if(!ready||opening)return;
        if(epub!=null){ReadingPreferences p=new ReadingPreferences(database);p.setReadingFontSize(p.readingFontSize()+direction);navigate(position,false);}
        else pdfView.zoomBy(direction<0?.8f:1.25f);
    }
    private ImageButton addReaderIcon(LinearLayout parent,int resource,String label,Runnable action) {
        ImageButton icon=ReaderChrome.icon(this,dark,resource,label,action);readerIcons.add(icon);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(48),dp(48));lp.leftMargin=dp(4);parent.addView(icon,lp);return icon;
    }
    private void setReaderMenus(boolean visible) {
        if(readerTopBar==null)return;readerMenusOpen=visible;
        readerTopBar.setVisibility(visible?View.VISIBLE:View.GONE);readerBottomBar.setVisibility(visible?View.VISIBLE:View.GONE);
        if(!visible)seekPanel.setVisibility(View.GONE);
    }
    private void applyKeepAwake() {
        boolean enabled=new ReadingPreferences(database).readingKeepScreenOn();
        if(enabled&&resumed)getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if(keepAwakeButton!=null)keepAwakeButton.setContentDescription(enabled?"关闭屏幕常亮":"保持屏幕常亮");
    }
    private void applyPdfTheme() {
        int background=dark?UiKit.DARK_BACKGROUND:UiKit.LIGHT_BACKGROUND,foreground=dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT,surface=dark?UiKit.DARK_SURFACE:UiKit.LIGHT_SURFACE;
        readerChrome.setBackgroundColor(background);pdfView.background(background);status.setTextColor(dark?UiKit.DARK_MUTED:UiKit.LIGHT_MUTED);
        readerTopBar.setBackground(UiKit.rounded(this,surface,22));readerBottomBar.setBackground(UiKit.rounded(this,surface,24));selectionBar.setBackground(UiKit.rounded(this,surface,22));
        for(ImageButton icon:readerIcons)UiKit.styleIconButton(this,icon,foreground,dark?UiKit.DARK_SURFACE_VARIANT:UiKit.LIGHT_SURFACE_VARIANT,14);
        for(Button b:new Button[]{copy,cancel,returnToReading,progressButton})UiKit.styleButton(this,b,Color.TRANSPARENT,foreground,14);
        LinearLayout zoom=(LinearLayout)readerTopBar.getChildAt(0);for(int i=0;i<zoom.getChildCount();i++)UiKit.styleButton(this,(Button)zoom.getChildAt(i),dark?UiKit.DARK_SURFACE_VARIANT:UiKit.LIGHT_SURFACE_VARIANT,foreground,14);
        themeButton.setImageResource(dark?R.drawable.ic_sun:R.drawable.ic_moon);seekPercentage.setTextColor(foreground);UiKit.styleReaderSeekBar(this,seekBar,dark);
        getWindow().setStatusBarColor(background);getWindow().setNavigationBarColor(background);
        getWindow().getDecorView().setSystemUiVisibility(dark?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
    }
    private LinearLayout row() { LinearLayout row = new LinearLayout(this); row.setGravity(Gravity.CENTER_VERTICAL); return row; }
    private Button button(String title, Runnable action) { Button b = new Button(this); b.setText(title); b.setTextSize(13); b.setMinWidth(0); b.setMinimumWidth(0); UiKit.styleButton(this,b,dark?UiKit.DARK_SURFACE_VARIANT:UiKit.LIGHT_SURFACE_VARIANT,dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT,UiKit.CONTROL_RADIUS);b.setOnClickListener(v -> action.run()); return b; }
    private int dp(int value) { return UiKit.dp(this, value); }

    private void showPdfCrop() {
        if (!ready || opening || pdf == null) return;
        clearSelection();
        PdfCropControls controls = new PdfCropControls(this, dark, settings -> pdfView.crop(settings));
        AlertDialog dialog = AppDialogs.builder(this,dark).setTitle("PDF 裁边").setView(controls)
                .setPositiveButton("完成", null).setNeutralButton("恢复原页", null).create();
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> controls.reset());
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setTextColor(dark?UiKit.DARK_ACCENT:UiKit.LIGHT_ACCENT);
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(dark?UiKit.DARK_ACCENT:UiKit.LIGHT_ACCENT);
        android.view.Window window=dialog.getWindow();
        if(window!=null){window.setGravity(Gravity.BOTTOM);window.setDimAmount(0);window.getDecorView().setSystemUiVisibility(dark?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);window.setBackgroundDrawable(UiKit.rounded(this,dark?UiKit.DARK_SURFACE:UiKit.LIGHT_SURFACE,24));window.setLayout(getResources().getDisplayMetrics().widthPixels-dp(24),-2);}
        setReaderMenus(false);
    }

    private void openPdf(String password, boolean retry) {
        opening = true; ready = false; status.setText("正在打开…"); final int request = ++generation;
        worker.execute(() -> {
            try {
                if (sourceHash == null) sourceHash = new BookHashCache(database).resolve(book.id, new File(book.path), () -> destroyed || request != generation).bookHash;
                ComicArchive.check(() -> destroyed || request != generation);
                String savedHash = database.documentHash(book.id);
                if (savedHash != null && !savedHash.equals(sourceHash)) throw new IllegalStateException("原文件已改变，旧位置不能应用；请重新导入");
                PdfDocument opened = new PdfDocument(this, new File(book.path), password);
                if(destroyed){close(opened);return;}
                pdf=opened;
                main.post(() -> {
                    if (destroyed || request != generation) { close(opened); return; }
                    pdf = opened;pdfSearchAvailable=false;nextTextProbe=0;textProbePending=false;
                    if (position == null) position = formal = DocumentLocator.pdf(0, pdf.pageCount, 0);
                    if (!"pdf".equals(position.format) || position.pageCount != pdf.pageCount) { openFailure("保存的位置与文档不匹配，已有数据保留。"); return; }
                    database.saveDocumentPosition(book, formal, sourceHash, readAt);
                    ready = true;
                    navigate(position, false, null, success -> { if(success) { opening=false; startSync(); } });
                });
            } catch (InvalidPasswordException error) { main.post(() -> { if (!destroyed && request == generation) password(retry || password != null); }); }
            catch (Exception error) { main.post(() -> { if (!destroyed && request == generation) openFailure("无法打开：文档损坏、格式/加密不支持或资源不足。已有位置已保留。"); }); }
        });
    }
    private void startSync() {
                    sync = new DocumentSyncSession(this, database, book, sourceHash, new DocumentSyncSession.Listener() {
                        public void remote(DocumentLocator target, long time, Runnable accepted, Runnable rejected) {
                            remoteDialog = AppDialogs.builder(DocumentReaderActivity.this,dark).setTitle("发现其他设备的阅读进度")
                                    .setMessage(String.format(Locale.getDefault(), "当前阅读进度 %.1f%%\n远端阅读进度 %.1f%%", formal.progress() * 100, target.progress() * 100))
                                    .setPositiveButton("前往", (d, w) -> {
                                        if (!valid(target)) { error("远端位置不能应用，已保留本地位置", false); rejected.run(); return; }
                                        navigate(target, false, time, success -> { if (success) accepted.run(); else rejected.run(); });
                                    }).setNegativeButton("保留当前", (d, w) -> rejected.run()).setOnCancelListener(d -> rejected.run()).show();
                        }
                        public void state(String text) { if (!destroyed && status != null) status.setContentDescription(text); }
                    });
                    sync.validateWith(this::valid);
                    if (resumed) sync.resume();
    }
    private void clearSelection() { if (epubView != null) epubView.clearSelection(); else if(pdfView!=null)pdfView.clearSelection(); }
    private void openEpub() {
        opening=true; ready=false;
        final int request=++generation; status.setText("正在打开电子书…");
        worker.execute(() -> {
            try {
                sourceHash=new BookHashCache(database).resolve(book.id,new File(book.path),()->destroyed||request!=generation).bookHash;
                ComicArchive.check(()->destroyed||request!=generation);
                String previous=database.documentHash(book.id);
                if(previous!=null&&!previous.equals(sourceHash))throw new IllegalStateException("原文件已改变");
                ReflowDocument opened="kindle".equals(book.format)?new KindleDocument(this,new File(book.path),()->destroyed||request!=generation):new EpubDocument(this,new File(book.path));
                if(destroyed){opened.close();return;} epub=opened;
                main.post(() -> {
                    if(destroyed||request!=generation){try{opened.close();}catch(Exception ignored){}return;}
                    epub=opened;epubSearchAvailable=false;
                    for(EpubDocument.Chapter chapter:epub.chapters)if(!chapter.text.replace("\ufffc", "").trim().isEmpty()){epubSearchAvailable=true;break;}
                    ReaderChrome.enabled(searchButton,epubSearchAvailable);
                    if(position==null)position=formal=epub.locator(0,0);
                    if(!epub.valid(position)){openFailure("保存的位置与正文不匹配，已保留原状态。");return;}
                    epubView=new EpubPageView(this,epub,new EpubPageView.Listener(){
                        public void moved(int offset){if(!resumed||!ready||opening||temporary||(sync!=null&&!sync.canRead()))return;int safe=ReaderTextSelection.boundary(epub.chapters.get(epub.chapterIndex(position)).text,offset);position=epub.locator(epub.chapterIndex(position),safe);commit(position,null);updateStatus();}
                        public void selected(String text){epubSelection=text;copy.setVisibility(text.isEmpty()?View.GONE:View.VISIBLE);cancel.setVisibility(text.isEmpty()?View.GONE:View.VISIBLE);selectionBar.setVisibility(!text.isEmpty()||temporary?View.VISIBLE:View.GONE);if(!text.isEmpty())setReaderMenus(false);}
                        public void tapped(){if(ready&&!opening)setReaderMenus(true);}
                        public boolean dismissMenus(){if(!readerMenusOpen)return false;setReaderMenus(false);return true;}
                        public void link(String href){followLink(href);}
                    });
                    content.removeAllViews(); content.addView(epubView,new FrameLayout.LayoutParams(-1,-1));ready=true;
                    navigate(position,false,null,success->{if(success){opening=false;database.saveDocumentPosition(book,formal,sourceHash,readAt);startSync();}});
                });
            }catch(Exception failure){main.post(()->{if(!destroyed&&request==generation)openFailure("电子书无法打开：结构/资源损坏、超出限额或格式暂不支持。已有数据保留。");});}
        });
    }
    private void followLink(String href) {
        try {
            java.net.URI uri=new java.net.URI(href);
            if(uri.getHost()!=null&&!"book.xlib.invalid".equals(uri.getHost())){
                if(!"https".equals(uri.getScheme())&&!"http".equals(uri.getScheme()))return;
                AppDialogs.builder(this,dark).setMessage("使用浏览器打开外部链接？").setPositiveButton("打开",(d,w)->startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,android.net.Uri.parse(href)))).setNegativeButton("取消",null).show();return;
            }
            String resource=EpubDocument.resolve(epub.chapters.get(epub.chapterIndex(position)).resource,href.replace("xlib-book://", "https://")),fragment=uri.getFragment();
            for(int i=0;i<epub.chapters.size();i++)if(epub.chapters.get(i).resource.equals(resource)){
                Integer offset=fragment==null?0:epub.chapters.get(i).anchors.get(fragment);
                if(offset==null){error("链接位置不存在",false);return;}
                navigate(epub.locator(i,offset),true);return;
            }
            error("链接目标不在支持的正文范围内",false);
        }catch(Exception e){error("链接无法打开",false);}
    }
    private void showToc(){if(!ready||opening||epub==null)return;String[] labels=new String[epub.toc.size()];for(int i=0;i<labels.length;i++)labels[i]=epub.toc.get(i).title;
        if(labels.length==0){error("此书没有有效内置目录，可继续按正文顺序阅读",false);return;}
        AppDialogs.builder(this,dark).setTitle("内置目录").setItems(labels,(d,w)->{EpubDocument.Toc target=epub.toc.get(w);navigate(epub.locator(target.chapter,target.offset),true);}).setNegativeButton("关闭",null).show();}
    private void preferences(){
        if(!ready||opening||epub==null)return;ReadingPreferences p=new ReadingPreferences(database);
        String[] options={"减小字号","增大字号","减小行距","增大行距","字体",dark?"浅色正文":"深色正文","开源许可"};
        AppDialogs.builder(this,dark).setTitle("阅读排版").setItems(options,(d,w)->{
            if(w==6){showReflowLicense();return;}
            if(w<2)p.setReadingFontSize(p.readingFontSize()+(w==0?-1:1));
            else if(w<4)p.setReadingLineSpacingRatio(p.readingLineSpacingRatio()+(w==2?-.02f:.02f));
            else if(w==4){
                String[] fonts={"系统","衬线","等宽","无衬线","仿宋（设备支持时）"};
                AppDialogs.builder(this,dark).setTitle("正文字体").setItems(fonts,(dialog,index)->{p.setReadingFontFamily(index);navigate(position,false);}).show();return;
            }else {
                dark=!dark;
                p.setAppTheme(dark?ReaderSettingsOptions.THEME_DARK:ReaderSettingsOptions.THEME_LIGHT);applyPdfTheme();
            }
            navigate(position,false);
        }).show();
    }
    private void showReflowLicense(){
        try(java.io.InputStream input=getAssets().open("kindle-LICENSE.txt")){
            java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[4096];int n;while((n=input.read(buffer))!=-1)bytes.write(buffer,0,n);
            TextView text=new TextView(this);text.setText(bytes.toString("UTF-8"));text.setTextColor(dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT);text.setPadding(dp(24),dp(12),dp(24),dp(12));
            AppDialogs.builder(this,dark).setTitle("开源许可").setView(AppDialogs.viewport(this,text)).setPositiveButton("关闭",null).show();
        }catch(Exception failure){error("无法读取开源许可",false);}
    }
    private static void close(PdfDocument document) { if (document != null) try { document.close(); } catch (Exception ignored) { } }
    private void openFailure(String message) {
        opening=false; ready=false;
        if (isFinishing() || destroyed) return;
        status.setText("打开失败");
        AppDialogs.builder(this,dark).setTitle("无法打开文档").setMessage(message)
                .setPositiveButton("重试打开", (d,w) -> retryOpen())
                .setNegativeButton("返回书架", (d,w) -> finish())
                .setOnCancelListener(d -> finish()).show();
    }
    private void retryOpen() {
        if (destroyed || isFinishing() || opening) return;
        ++generation; ready=false; stopSearch(); clearSelection();
        if(sync!=null){sync.close();sync=null;}
        temporary=false; selectedSearchHit=null; searchHits.clear();
        returnToReading.setVisibility(View.GONE);
        position=formal; sourceHash=null;
        displayedPdfPage=-1;
        pdfView.release();
        if(epubView!=null){content.removeView(epubView);epubView.release();epubView=null;}
        PdfDocument previousPdf=pdf; ReflowDocument previousEpub=epub; pdf=null; epub=null;
        worker.execute(() -> {
            close(previousPdf);
            if(previousEpub!=null)try{previousEpub.close();}catch(Exception ignored){}
        });
        // A new attempt never retains a password or bypasses source-hash validation.
        if(isEpub())openEpub();else openPdf(null,false);
    }
    private void password(boolean wrong) {
        EditText input = new EditText(this); input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        input.setSaveEnabled(false); input.setHint("打开密码");
        AlertDialog dialog = AppDialogs.builder(this,dark).setTitle(wrong ? "密码错误，请重试" : "此 PDF 需要密码")
                .setView(input).setPositiveButton("打开", null).setNegativeButton("取消", (d, w) -> { input.setText(""); finish(); })
                .setOnCancelListener(d -> { input.setText(""); finish(); }).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String value = input.getText().toString(); input.setText(""); dialog.dismiss(); openPdf(value, true);
        })); dialog.show();
    }
    private boolean valid(DocumentLocator target) { if(epub!=null)return epub.valid(target); return target != null && "pdf".equals(target.format) && pdf != null && target.pageCount == pdf.pageCount && target.page < pdf.pageCount; }
    private interface NavigationResult { void completed(boolean success); }
    private boolean commit(DocumentLocator target, Long preservedTime) {
        if (preservedTime == null && target.equals(formal)) return true;
        long nextTime=preservedTime==null ? SyncRules.monotonicReadAt(System.currentTimeMillis(),readAt) : preservedTime;
        try { database.saveDocumentPosition(book,target,sourceHash,nextTime); }
        catch(Exception failure){error("阅读位置保存失败，已有进度保留，请检查设备存储空间",false);return false;}
        formal=target;readAt=nextTime;
        if(sync!=null&&preservedTime==null)sync.moved();
        return true;
    }
    private void updateStatus() {
        status.setText(locationLabel(position));
        if(progressButton!=null){
            if(isEpub()&&epub==null){String value=String.format(Locale.getDefault(),"%.1f%%",position.progress()*100);progressButton.setText(value);seekPercentage.setText(value);return;}
            progressButton.setText(String.format(Locale.getDefault(),"%d / %d\n%.1f%%",isEpub()?epub.chapterIndex(position)+1:position.page+1,isEpub()?epub.chapters.size():position.pageCount,position.progress()*100));
            if(!seekTracking){seekBar.setMax(epub instanceof KindleDocument?position.textLength:Math.max(0,(isEpub()?epub.chapters.size():position.pageCount)-1));seekBar.setProgress(epub instanceof KindleDocument?position.textOffset:isEpub()?epub.chapterIndex(position):position.page);seekPercentage.setText(String.format(Locale.getDefault(),"%.1f%%",position.progress()*100));}
        }
    }
    private String locationLabel(DocumentLocator p) {
        if(epub==null&&"kindle".equals(p.format))return String.format(Locale.getDefault(),"%.1f%%",p.progress()*100);
        return String.format(Locale.getDefault(), "第 %d / %d %s · %.1f%%", "pdf".equals(p.format)?p.page+1:epub==null?p.spineIndex+1:epub.chapterIndex(p)+1, "pdf".equals(p.format)?p.pageCount:epub==null?p.spineCount:epub.chapters.size(), "pdf".equals(p.format)?"页":"章", p.progress()*100);
    }
    private void navigate(DocumentLocator target, boolean user) { navigate(target, user, null, success -> { }); }
    private void navigate(DocumentLocator target, boolean user, Long preservedTime, NavigationResult completion) {
        if (!ready || !valid(target)) { if (ready) error("位置无法应用，已保留原阅读位置", false); completion.completed(false); return; }
        if (opening && user) { completion.completed(false); return; }
        if (user && !temporary && sync != null && !sync.canRead()) { completion.completed(false); return; }
        int request = ++generation;
        if(epub!=null){ReaderChrome.enabled(copy,!epub.chapters.get(epub.chapterIndex(target)).text.replace("\ufffc", "").trim().isEmpty());ReadingPreferences p=new ReadingPreferences(database);epubSelection="";copy.setVisibility(View.GONE);cancel.setVisibility(View.GONE);
            epubView.show(target,dark,p.readingFontSize(),1+p.readingLineSpacingRatio(),p.readingFontFamily(),success->{
                if(destroyed||request!=generation||(!resumed&&(user||preservedTime!=null))){completion.completed(false);return;}
                if(!success){if(opening)openFailure("正文定位映射失败，已有位置保留。");else error("正文定位映射失败，已有位置保留",false);completion.completed(false);return;}
                position=target;if(temporary&&selectedSearchHit!=null&&target.equals(selectedSearchHit.locator))epubView.highlight(selectedSearchHit.start,selectedSearchHit.end-selectedSearchHit.start);if((preservedTime!=null||(user&&!temporary))&&!commit(target,preservedTime)){completion.completed(false);return;}updateStatus();completion.completed(true);
            });return;
        }
        if(target.page==displayedPdfPage){
            position=target;pdfView.position(target.y);
            if(temporary&&selectedSearchHit!=null&&target.equals(selectedSearchHit.locator))pdfView.highlight(selectedSearchHit.start,selectedSearchHit.end);
            if((preservedTime!=null||(user&&!temporary))&&!commit(target,preservedTime)){completion.completed(false);return;}
            updateStatus();completion.completed(true);return;
        }
        PdfDocument.Page cached=pdfView.cachedPage(target.page);
        if(cached!=null){
            position=target;displayedPdfPage=target.page;pdfView.page(cached,target.y,target.page);updatePdfTextActions(cached);
            if(temporary&&selectedSearchHit!=null&&target.equals(selectedSearchHit.locator))pdfView.highlight(selectedSearchHit.start,selectedSearchHit.end);
            if((preservedTime!=null||(user&&!temporary))&&!commit(target,preservedTime)){completion.completed(false);return;}
            updateStatus();completion.completed(true);return;
        }
        worker.execute(() -> {
            if(destroyed||request!=generation){main.post(()->completion.completed(false));return;}
            try {
                PdfDocument.Page result = pdf.render(target.page, getResources().getDisplayMetrics().widthPixels);
                main.post(() -> {
                    if (destroyed || request != generation) { result.bitmap.recycle(); completion.completed(false); return; }
                    if(!resumed&&(user||preservedTime!=null)){result.bitmap.recycle();completion.completed(false);return;}
                    position = target; displayedPdfPage=target.page;pdfView.page(result, target.y,target.page);updatePdfTextActions(result);
                    if(temporary&&selectedSearchHit!=null&&target.equals(selectedSearchHit.locator))pdfView.highlight(selectedSearchHit.start,selectedSearchHit.end);
                    if ((preservedTime != null || (user && !temporary)) && !commit(target, preservedTime)) { completion.completed(false); return; }
                    updateStatus(); completion.completed(true);
                });
            } catch (Exception e) { main.post(() -> { if (!destroyed && request == generation) {
                String message=e.getMessage()!=null&&e.getMessage().contains("JPEG2000/JBIG2")?"此页包含暂不支持的 JPEG2000/JBIG2 图片编码，已有进度保留":"页面读取失败，已有进度保留";
                if(opening)openFailure(message);else error(message,false);
                completion.completed(false);
            } }); }
        });
    }
    private void updatePdfTextActions(PdfDocument.Page page) {
        boolean selectable=pdf.mayExtract&&!page.text.trim().isEmpty();
        ReaderChrome.enabled(copy,selectable);
        if(selectable)pdfSearchAvailable=true;
        ReaderChrome.enabled(searchButton,pdfSearchAvailable);
        probePdfText();
    }
    /** Probe incrementally after first display; navigation can run between pages. */
    private void probePdfText() {
        PdfDocument session=pdf;
        if(destroyed||!resumed||!ready||session==null||!session.mayExtract||pdfSearchAvailable||textProbePending||nextTextProbe>=session.pageCount)return;
        int index=nextTextProbe++;textProbePending=true;
        worker.execute(()->{
            boolean found=false;
            try{found=!session.searchText(index,()->destroyed).trim().isEmpty();}catch(Exception ignored){}
            boolean available=found;
            main.post(()->{
                if(destroyed||pdf!=session)return;
                textProbePending=false;
                if(available){pdfSearchAvailable=true;ReaderChrome.enabled(searchButton,true);}
                else probePdfText();
            });
        });
    }
    private void step(int delta) {
        if(epub!=null){if(ready&&epubSelection.isEmpty()){int unit=Math.max(0,Math.min(epub.chapters.size()-1,epub.chapterIndex(position)+delta));navigate(epub.locator(unit,0),true);}return;}
        if (ready && !pdfView.hasSelection()) navigate(DocumentLocator.pdf(Math.max(0, Math.min(pdf.pageCount - 1, position.page + delta)), pdf.pageCount, 0), true);
    }
    private void jump() {
        if (!ready || opening) return;
        if(epub!=null){String[] labels=new String[epub.chapters.size()];for(int i=0;i<labels.length;i++)labels[i]="第 "+(i+1)+" 章";AppDialogs.builder(this,dark).setTitle("前往章节").setItems(labels,(d,w)->navigate(epub.locator(w,0),true)).show();return;}
        EditText input = new EditText(this); input.setInputType(InputType.TYPE_CLASS_NUMBER); input.setHint("1–" + pdf.pageCount);
        AlertDialog d = AppDialogs.builder(this,dark).setTitle("前往页码").setView(input).setPositiveButton("前往", null).setNegativeButton("取消", null).create();
        d.setOnShowListener(ignored -> d.getButton(-1).setOnClickListener(v -> { try {
            int page = Integer.parseInt(input.getText().toString());
            if (page < 1 || page > pdf.pageCount) throw new IllegalArgumentException();
            navigate(DocumentLocator.pdf(page - 1, pdf.pageCount, 0), true); d.dismiss();
        } catch (Exception e) { input.setError("请输入有效页码"); } })); d.show();
    }
    private void showBookmarks() {
        if (!ready || opening) return;
        LinearLayout list = new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL);
        AlertDialog dialog = AppDialogs.builder(this,dark).setTitle("本地书签").setView(list).setNegativeButton("关闭", null).create();
        list.addView(button("添加当前位置", () -> { boolean added = database.addDocumentBookmark(book.id, position); dialog.dismiss(); error(added ? "已添加书签" : "当前位置已有书签", false); }));
        List<LocalDatabase.DocumentBookmark> bookmarks = database.documentBookmarks(book.id);
        ScrollView scroll = new ScrollView(this); LinearLayout rows = new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL); scroll.addView(rows); list.addView(scroll);
        for (LocalDatabase.DocumentBookmark mark : bookmarks) {
            LinearLayout row = row();
            row.addView(button(locationLabel(mark.locator), () -> { dialog.dismiss(); navigate(mark.locator, true); }));
            row.addView(button("删除", () -> AppDialogs.builder(this,dark).setMessage("删除此书签？")
                    .setPositiveButton("删除", (d, w) -> { database.deleteDocumentBookmark(book.id, mark.id); dialog.dismiss(); showBookmarks(); }).setNegativeButton("取消", null).show())); rows.addView(row);
        }
        if (bookmarks.isEmpty()) { TextView empty = new TextView(this); empty.setText("暂无书签"); rows.addView(empty); }
        dialog.show();
    }
    private DocumentSearch.Source searchSource() {
        if(epub!=null)return new DocumentSearch.Source(){public int units(){return epub.chapters.size();}public String text(int unit){return epub.searchText(unit);}public DocumentLocator locator(int unit,int offset){return epub.locator(unit,offset);}};
        return new DocumentSearch.Source() {
            PdfDocument.Text last; int lastPage = -1;
            public int units() { return pdf.pageCount; }
            public String text(int unit) throws Exception {
                return text(unit, () -> false);
            }
            public String text(int unit, DocumentSearch.Cancellation cancelled) throws Exception {
                if(lastPage==unit&&last!=null)return last.value;
                last=null;lastPage=unit;return pdf.searchText(unit,cancelled);
            }
            public DocumentLocator locator(int unit, int offset) throws Exception {
                return locator(unit, offset, () -> false);
            }
            public DocumentLocator locator(int unit, int offset, DocumentSearch.Cancellation cancelled) throws Exception {
                if(lastPage!=unit||last==null){last=pdf.text(unit,cancelled);lastPage=unit;}
                float height = pdfHeight(unit);
                double y = offset < last.boxes.size() ? Math.max(0, Math.min(1, last.boxes.get(offset).top / height)) : 0;
                return DocumentLocator.pdf(unit, pdf.pageCount, y);
            }
        };
    }
    private float pdfHeight(int unit) { return pdf.pageHeight(unit); }
    private void showSearch() {
        if (!ready || opening || searching) return;
        if(temporary&&search!=null){showSearchResults();return;}
        if (pdf!=null ? !pdfSearchAvailable : !epubSearchAvailable) return;
        EditText input = new EditText(this); input.setHint("2–32 个字符");input.setText(lastSearchQuery);
        android.widget.CheckBox fromBeginning=new android.widget.CheckBox(this);fromBeginning.setText("从书首搜索");
        LinearLayout form=new LinearLayout(this);form.setOrientation(LinearLayout.VERTICAL);form.addView(input);form.addView(fromBeginning);
        AppDialogs.builder(this,dark).setTitle("搜索文档").setView(form).setPositiveButton("搜索", (d, w) ->
                beginSearch(input.getText().toString(),fromBeginning.isChecked())).setNegativeButton("取消", null).show();
    }
    private void beginSearch(String query,boolean fromBeginning) {
        stopSearch();lastSearchQuery=query;
        try {
            search=new DocumentSearch(query,fromBeginning?0:epub==null?position.page:epub.chapterIndex(position),
                    fromBeginning?0:epub==null?pdfView.firstTextOffset(position.y):epub.localOffset(position));
            activeSearchSource=searchSource();
            searchHits.clear();loadSearch();
        } catch(IllegalArgumentException failure) {error(failure.getMessage(),false);}
    }
    private void dismissSearchDialog() {
        if(searchDialog!=null){AlertDialog dialog=searchDialog;searchDialog=null;dialog.dismiss();}
    }
    private void stopSearch() {
        if(search!=null)search.cancel();search=null;activeSearchSource=null;searching=false;
        dismissSearchDialog();if(position!=null)updateStatus();
    }
    private void loadSearch() {
        if(search==null||searching)return;
        status.setText("正在搜索…"); DocumentSearch requested = search;
        DocumentSearch.Source source=activeSearchSource;
        searching=true;dismissSearchDialog();
        searchDialog=AppDialogs.builder(this,dark).setTitle("正在搜索文档…")
                .setMessage("可停止搜索并继续阅读，阅读进度不会改变。")
                .setNegativeButton("停止搜索",(d,w)->stopSearch()).setOnCancelListener(d->stopSearch()).show();
        worker.execute(() -> {
            try {
                List<DocumentSearch.Hit> batch = requested.next(source);
                main.post(() -> { if (destroyed || !resumed || requested != search) return;
                    searching=false;dismissSearchDialog();updateStatus();searchHits.addAll(batch);showSearchResults(); });
            } catch (Exception e) { main.post(() -> { if (!destroyed && resumed && requested==search) {
                stopSearch();error("搜索失败，请重试", false);
            } }); }
        });
    }
    private void showSearchResults() {
        String[] labels = new String[searchHits.size()];
        for (int i = 0; i < labels.length; i++) labels[i] = locationLabel(searchHits.get(i).locator) + "：" + searchHits.get(i).snippet;
        AlertDialog.Builder builder = AppDialogs.builder(this,dark).setTitle("已加载 " + labels.length + " 条" + (search.complete ? " · 当前范围结束" : ""))
                .setItems(labels, (d, index) -> { temporary = true; returnToReading.setVisibility(View.VISIBLE);selectionBar.setVisibility(View.VISIBLE); if (sync != null) sync.temporary(true); selectedSearchHit=searchHits.get(index); navigate(selectedSearchHit.locator, false); })
                .setNegativeButton("关闭", null);
        if (search.needsWrap) builder.setPositiveButton("从开头继续", (d, w) -> { search.wrap(); loadSearch(); });
        else if (!search.complete) builder.setPositiveButton("继续加载", (d, w) -> loadSearch());
        searchDialog=builder.show();
    }
    private void showSync() {
        if (sync == null) { error("打开文档并完成解锁后可同步", false); return; }
        AppDialogs.builder(this,dark).setTitle("阅读进度同步").setMessage(sync.message())
                .setPositiveButton("刷新比较", (d, w) -> sync.refresh())
                .setNeutralButton("删除本书云端进度", (d, w) -> AppDialogs.builder(this,dark).setMessage("仅删除本书云端进度，本地数据保留；本次阅读暂停上传。")
                        .setPositiveButton("删除", (a, b) -> sync.delete()).setNegativeButton("取消", null).show())
                .setNegativeButton("关闭", null).show();
    }
    private void error(String message, boolean leave) {
        if (isFinishing() || destroyed) return;
        AppDialogs.builder(this,dark).setMessage(message).setPositiveButton(leave ? "返回书架" : "确定", (d, w) -> { if (leave) finish(); })
                .setOnCancelListener(d -> { if (leave) finish(); }).show();
    }
    @Override public void onBackPressed() {
        if (!epubSelection.isEmpty() || (pdfView != null && pdfView.hasSelection())) { clearSelection(); return; }
        if(readerMenusOpen){setReaderMenus(false);return;}
        if (temporary) { temporary = false; if (sync != null) sync.temporary(false); returnToReading.setVisibility(View.GONE); navigate(formal, false); return; }
        super.onBackPressed();
    }
    @Override protected void onResume() {
        super.onResume();resumed=true;
        if(pdfView!=null)pdfView.crop(PdfCropSettings.current());
        probePdfText();
        if(database!=null&&new ReadingPreferences(database).readingKeepScreenOn())getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if(sync!=null)sync.resume();
    }
    @Override protected void onPause() {
        resumed=false;stopSearch();clearSelection();
        getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if(sync!=null)sync.pause();if(remoteDialog!=null){remoteDialog.dismiss();remoteDialog=null;}super.onPause();
    }
    @Override public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (!destroyed && level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            if(pdfView!=null)pdfView.trimPages(true);
            PdfDocument session=pdf;
            if(session!=null)worker.execute(session::clearSearchCache);
        }
    }
    @Override protected void onDestroy() {
        destroyed = true; generation++; if(search!=null)search.cancel(); main.removeCallbacksAndMessages(null);
        if (sync != null) sync.close(); if (pdfView != null) pdfView.release(); if(epubView!=null)epubView.release();
        worker.execute(() -> { close(pdf); if(epub!=null)try{epub.close();}catch(Exception ignored){} if (database != null) database.close(); }); worker.shutdown();
        super.onDestroy();
    }
}
