package com.xlib.txtreader;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;

/** Bitmap and text geometry share the same document-to-screen transform. */
final class PdfPageView extends View {
    interface Listener {
        void selectionChanged(boolean selected); void panned(double y);
        default void tapped(float fraction) { }
        default void turned(int direction) { }
        default boolean dismissMenus() { return false; }
    }
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final GestureDetector gestures;
    private final ScaleGestureDetector scales;
    private final Listener listener;
    private PdfDocument.Page page;
    private PdfCropSettings crop = PdfCropSettings.current();
    private float zoom = 1, dx, dy, lastX, lastY, movement;
    private int start = -1, end = -1, wordStart, wordEnd, handle;
    private boolean pinched;
    private int highlightStart=-1,highlightEnd;
    private int background = UiKit.LIGHT_BACKGROUND;
    private boolean dismissTouch, turned;
    private final RectF drawBounds = new RectF(), clipBounds = new RectF();
    static final int PAGE_CACHE_BYTES=12*1024*1024;
    private final java.util.LinkedHashMap<Integer,PdfDocument.Page> pageCache=new java.util.LinkedHashMap<>(4,.75f,true);

    PdfPageView(Context context, Listener listener) {
        super(context); this.listener = listener; setContentDescription("PDF 页面；双指缩放，长按拖动选择文字");
        gestures = new GestureDetector(context, new GestureDetector.SimpleOnGestureListener() {
            @Override public boolean onDown(MotionEvent e) { return true; }
            @Override public boolean onSingleTapConfirmed(MotionEvent e) {
                if(page!=null&&!hasSelection())listener.tapped(e.getX()/Math.max(1,getWidth()));return true;
            }
            @Override public boolean onFling(MotionEvent a,MotionEvent b,float vx,float vy) {
                if(a==null||page==null||hasSelection()||pinched||zoom>1)return false;
                float x=b.getX()-a.getX(),y=b.getY()-a.getY();
                if(Math.abs(x)<density(72)||Math.abs(x)<Math.abs(y)*1.5f)return false;
                turned=true;listener.turned(x<0?1:-1);return true;
            }
            @Override public void onLongPress(MotionEvent e) {
                int index = character(e.getX(), e.getY());
                if (index < 0) return;
                RectF target=box(index);target.inset(-density(10),-density(10));if(!target.contains(e.getX(),e.getY()))return;
                int[] word = ReaderTextSelection.wordAt(page.text, index);
                start = wordStart = word[0]; end = wordEnd = word[1]; handle = 0;
                listener.selectionChanged(true); invalidate();
            }
            @Override public boolean onDoubleTap(MotionEvent e) {
                double y = visibleY(); zoom = zoom > 1 ? 1 : 2; dx = dy = 0;
                if (crop.enabled) restoreY(y);
                invalidate(); return true;
            }
        });
        scales = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScale(ScaleGestureDetector detector) {
                pinched = true; zoom = Math.max(1, Math.min(5, zoom * detector.getScaleFactor())); clampPan(); invalidate(); return true;
            }
        });
    }

    void background(int color) { background=color;invalidate(); }
    void zoomBy(float factor) {
        if(page==null)return;double y=visibleY();zoom=Math.max(1,Math.min(5,zoom*factor));dx=0;restoreY(y);clearSelection();invalidate();
    }
    void position(double y) { if(page==null)return;highlightStart=-1;clearSelection();restoreY(y);invalidate(); }

    void page(PdfDocument.Page value, double y) {
        page(value,y,-1);
    }
    void page(PdfDocument.Page value,double y,int index) {
        PdfDocument.Page old = page; page = value; highlightStart=-1; zoom = 1; dx = dy = 0; clearSelection();
        crop = PdfCropSettings.current();
        if(index>=0)pageCache.put(index,value);
        if(old!=null&&old.bitmap!=value.bitmap&&!pageCache.containsValue(old))old.bitmap.recycle();
        trimPages(false);
        post(() -> { if (page == value) { if(y>0&&!crop.enabled)zoom=2;restoreY(y);invalidate(); } });
    }
    PdfDocument.Page cachedPage(int index){PdfDocument.Page cached=pageCache.get(index);return cached==null||cached.bitmap.isRecycled()?null:cached;}
    void trimPages(boolean all){
        long bytes=0;for(PdfDocument.Page cached:pageCache.values())bytes+=cached.bitmap.getAllocationByteCount();
        java.util.Iterator<PdfDocument.Page> iterator=pageCache.values().iterator();
        while(iterator.hasNext()){
            PdfDocument.Page cached=iterator.next();if(cached==page)continue;
            if(all||bytes>PAGE_CACHE_BYTES||pageCache.size()>3){bytes-=cached.bitmap.getAllocationByteCount();iterator.remove();cached.bitmap.recycle();}
        }
    }

    /** Display-only transform; never emits a reading-position event. */
    void crop(PdfCropSettings settings) {
        if (crop.equals(settings)) return;
        double y = page == null ? 0 : visibleY();
        crop = settings; zoom = 1; dx = 0; clearSelection();
        if (page != null) restoreY(y);
        invalidate();
    }

    void highlight(int start,int end) {
        if(page==null||start<0||end>page.text.length()||end<=start)return;
        highlightStart=start;highlightEnd=end;
        post(()->{if(page==null||highlightStart!=start||start>=page.boxes.size())return;RectF hit=box(start);dx+=getWidth()/2f-hit.centerX();dy+=getHeight()/3f-hit.centerY();clampPan();invalidate();});
        invalidate();
    }
    void clearSelection() { start = end = -1; listener.selectionChanged(false); invalidate(); }
    String selectedText() { return page == null || start < 0 ? "" : page.text.substring(start, end); }
    boolean hasSelection() { return start >= 0; }
    boolean hasNoText() { return page!=null&&page.text.trim().isEmpty(); }
    int firstTextOffset(double y) {
        if(page==null)return 0;
        for(int i=0;i<page.boxes.size();i++)if(!page.boxes.get(i).isEmpty()&&page.boxes.get(i).top/page.height>=y)return i;
        return page.text.length();
    }
    void release() { for(PdfDocument.Page cached:pageCache.values())if(!cached.bitmap.isRecycled())cached.bitmap.recycle();pageCache.clear();if(page!=null&&!page.bitmap.isRecycled())page.bitmap.recycle();page=null; }
    private void clampPan(){if(page==null)return;float x=Math.max(0,(croppedWidth()*scale()-getWidth())/2),y=Math.max(0,(page.bitmap.getHeight()*scale()-getHeight())/2);dx=Math.max(-x,Math.min(x,dx));dy=Math.max(-y,Math.min(y,dy));}
    private float density(float value){return value*getResources().getDisplayMetrics().density;}
    private float croppedWidth() { return page.bitmap.getWidth() * (1 - crop.leftFraction() - crop.rightFraction()); }
    private float fit(int width, int height) {
        if (page == null || width <= 0 || height <= 0) return 1;
        return crop.enabled ? width / croppedWidth() : Math.min(width / (float)page.bitmap.getWidth(), height / (float)page.bitmap.getHeight());
    }
    private float fit() { return fit(getWidth(), getHeight()); }
    private float scale() { return fit() * zoom; }
    private float left() { return (getWidth() - croppedWidth() * scale()) / 2 + dx - page.bitmap.getWidth()*crop.leftFraction()*scale(); }
    private float top() { return (getHeight() - page.bitmap.getHeight() * scale()) / 2 + dy; }
    private double visibleY() { return Math.max(0, Math.min(1, -top() / (page.bitmap.getHeight() * scale()))); }
    private void restoreY(double y) {
        float height = page.bitmap.getHeight()*scale();
        dy = -(float)y*height - (getHeight()-height)/2;
        clampPan();
    }
    private RectF visiblePage() {
        return new RectF(left()+page.bitmap.getWidth()*crop.leftFraction()*scale(), top(),
                left()+page.bitmap.getWidth()*(1-crop.rightFraction())*scale(), top()+page.bitmap.getHeight()*scale());
    }
    @Override protected void onSizeChanged(int w,int h,int oldw,int oldh) {
        super.onSizeChanged(w,h,oldw,oldh);
        if(page==null||oldw<=0||oldh<=0||w<=0||h<=0)return;
        float oldHeight=page.bitmap.getHeight()*fit(oldw,oldh)*zoom;
        double y=Math.max(0,Math.min(1,-((oldh-oldHeight)/2+dy)/oldHeight));
        restoreY(y);invalidate();
    }
    private RectF box(int index) {
        RectF b = page.boxes.get(index);
        float sx = page.bitmap.getWidth() / page.width * scale(), sy = page.bitmap.getHeight() / page.height * scale();
        return new RectF(left() + b.left * sx, top() + b.top * sy, left() + b.right * sx, top() + b.bottom * sy);
    }
    private int character(float x, float y) {
        if (page == null || page.text.isEmpty() || !visiblePage().contains(x,y)) return -1;
        float distance = Float.MAX_VALUE; int result = -1;
        RectF visible = visiblePage();
        float sx=page.bitmap.getWidth()/page.width*scale(),sy=page.bitmap.getHeight()/page.height*scale(),left=left(),top=top();
        for (int i = 0; i < Math.min(page.text.length(), page.boxes.size()); i++) {
            RectF b=page.boxes.get(i);if(b.isEmpty())continue;
            float bl=left+b.left*sx,br=left+b.right*sx,bt=top+b.top*sy,bb=top+b.bottom*sy;
            if(bl>=visible.right||br<=visible.left||bt>=visible.bottom||bb<=visible.top)continue;
            float cx=(bl+br)/2-x,cy=(bt+bb)/2-y,d=cx*cx+cy*cy;
            if (d < distance) { distance = d; result = i; }
        }
        return result;
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas); canvas.drawColor(background);
        if (page == null || page.bitmap.isRecycled()) return;
        float scale=scale(),left=left(),top=top();
        clipBounds.set(left+page.bitmap.getWidth()*crop.leftFraction()*scale,top,left+page.bitmap.getWidth()*(1-crop.rightFraction())*scale,top+page.bitmap.getHeight()*scale);
        int save = canvas.save(); canvas.clipRect(clipBounds);
        paint.setColor(Color.WHITE);
        drawBounds.set(left,top,left+page.bitmap.getWidth()*scale,top+page.bitmap.getHeight()*scale);
        canvas.drawBitmap(page.bitmap, null, drawBounds, paint);
        if(highlightStart>=0){paint.setColor(0x99ffcc44);for(int i=highlightStart;i<Math.min(highlightEnd,page.boxes.size());i++)if(!page.boxes.get(i).isEmpty())canvas.drawRect(box(i),paint);}
        if (start >= 0) {
            paint.setColor(0x7789D8C5);
            for (int i = start; i < Math.min(end, page.boxes.size()); i++) if (!page.boxes.get(i).isEmpty()) canvas.drawRect(box(i), paint);
        }
        if (start >= 0 && end > start && end <= page.boxes.size()) {
            paint.setColor(0xff0e473c);
            RectF a = box(start), b = box(end - 1);
            canvas.drawCircle(a.left, a.bottom, density(9), paint); canvas.drawCircle(b.right, b.bottom, density(9), paint);
        }
        canvas.restoreToCount(save);
    }

    @Override public boolean onTouchEvent(MotionEvent event) {
        if (page == null) return true;
        if(event.getActionMasked()==MotionEvent.ACTION_DOWN){dismissTouch=listener.dismissMenus();turned=false;}
        if(dismissTouch){if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL)dismissTouch=false;return true;}
        scales.onTouchEvent(event); gestures.onTouchEvent(event);
        float x = event.getX(), y = event.getY();
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            lastX = x; lastY = y; movement = 0; pinched = false; handle = 0;
            if (start >= 0 && end > start) {
                RectF a = box(start), b = box(end - 1);
                if (Math.hypot(x - a.left, y - a.bottom) < density(24)) handle = 1;
                else if (Math.hypot(x - b.right, y - b.bottom) < density(24)) handle = 2;
            }
        } else if (event.getActionMasked() == MotionEvent.ACTION_MOVE && !scales.isInProgress()) {
            if (start >= 0) {
                int index = character(x, y);
                if (index >= 0) {
                    index = ReaderTextSelection.boundary(page.text, index);
                    if (handle == 1) start = Math.min(index, ReaderTextSelection.boundary(page.text,end-1));
                    else if (handle == 2) end = Math.max(ReaderTextSelection.nextBoundary(page.text,start), ReaderTextSelection.wordAt(page.text, index)[1]);
                    else { int[] range = ReaderTextSelection.dragFromWord(page.text, wordStart, wordEnd, index); start = range[0]; end = range[1]; }
                }
            } else if (zoom > 1 || (crop.enabled && page.bitmap.getHeight()*scale()>getHeight())) { float oldX=dx,oldY=dy;dx += x - lastX; dy += y - lastY; clampPan(); movement += Math.abs(dx-oldX) + Math.abs(dy-oldY); }
            lastX = x; lastY = y; invalidate();
        } else if (event.getActionMasked() == MotionEvent.ACTION_UP) {
            if (movement > 8 && !pinched && !turned && start < 0) listener.panned(visibleY());
            performClick();
        } else if (event.getActionMasked() == MotionEvent.ACTION_CANCEL) handle = 0;
        return true;
    }
    @Override public boolean performClick() { super.performClick(); return true; }
}
