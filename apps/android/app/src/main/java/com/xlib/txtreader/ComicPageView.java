package com.xlib.txtreader;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;

/** Image content only; menus and reading state belong to the hosting reader. */
final class ComicPageView extends View {
    interface Listener {
        void tap(float fraction);
        void turn(int direction);
        boolean dismissMenus();
        default void moved(double y){}
    }
    private final Listener listener;
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
    private final RectF bounds=new RectF();
    private final GestureDetector gestures;
    private final ScaleGestureDetector scales;
    private Bitmap bitmap;
    private boolean fitWidth=true,dismissTouch,pinched,turned;
    private float zoom=1,dx,top,lastX,lastY,downX,downY;
    private double anchor;
    private int background=UiKit.LIGHT_BACKGROUND;

    ComicPageView(Context context,Listener listener) {
        super(context);this.listener=listener;setContentDescription("漫画页面；左右翻页，双指缩放，上下拖动查看长图");
        gestures=new GestureDetector(context,new GestureDetector.SimpleOnGestureListener(){
            @Override public boolean onDown(MotionEvent event){return true;}
            @Override public boolean onSingleTapConfirmed(MotionEvent event){listener.tap(event.getX()/Math.max(1,getWidth()));return true;}
            @Override public boolean onDoubleTap(MotionEvent event){zoom(zoom>1?.5f:2,event.getX(),event.getY());return true;}
            @Override public boolean onFling(MotionEvent a,MotionEvent b,float vx,float vy){
                return a!=null&&turn(b.getX()-a.getX(),b.getY()-a.getY());
            }
        });
        scales=new ScaleGestureDetector(context,new ScaleGestureDetector.SimpleOnScaleGestureListener(){
            @Override public boolean onScale(ScaleGestureDetector detector){pinched=true;zoom(detector.getScaleFactor(),detector.getFocusX(),detector.getFocusY());return true;}
        });
    }
    void page(Bitmap value,double y) {bitmap=value;zoom=1;dx=0;anchor=Math.max(0,Math.min(1,y));restore();invalidate();}
    void background(int color){background=color;invalidate();}
    boolean fitWidth(){return fitWidth;}
    void fitWidth(boolean value){fitWidth=value;zoom=1;dx=0;restore();invalidate();}
    double anchor(){return anchor;}
    void release(){bitmap=null;invalidate();}
    void zoomBy(float factor){zoom(factor,getWidth()/2f,getHeight()/2f);}
    private float scale(){if(bitmap==null||getWidth()==0||getHeight()==0)return 1;float width=getWidth()/(float)bitmap.getWidth();return (fitWidth?width:Math.min(width,getHeight()/(float)bitmap.getHeight()))*zoom;}
    private float left(){return bitmap==null?0:(getWidth()-bitmap.getWidth()*scale())/2+dx;}
    private void restore(){if(bitmap==null)return;top=-(float)anchor*bitmap.getHeight()*scale();clamp();}
    private void clamp(){if(bitmap==null)return;float width=bitmap.getWidth()*scale(),height=bitmap.getHeight()*scale();dx=Math.max(-Math.max(0,(width-getWidth())/2),Math.min(Math.max(0,(width-getWidth())/2),dx));top=height<=getHeight()?(getHeight()-height)/2:Math.max(getHeight()-height,Math.min(0,top));}
    private void zoom(float factor,float x,float y){
        if(bitmap==null)return;float old=scale(),oldLeft=left(),oldTop=top;zoom=Math.max(1,Math.min(5,zoom*factor));float ratio=scale()/old;
        dx=x-(x-oldLeft)*ratio-(getWidth()-bitmap.getWidth()*scale())/2;top=y-(y-oldTop)*ratio;clamp();invalidate();
    }
    @Override protected void onSizeChanged(int w,int h,int oldw,int oldh){super.onSizeChanged(w,h,oldw,oldh);restore();}
    @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);canvas.drawColor(background);if(bitmap==null||bitmap.isRecycled())return;bounds.set(left(),top,left()+bitmap.getWidth()*scale(),top+bitmap.getHeight()*scale());canvas.drawBitmap(bitmap,null,bounds,paint);}
    @Override public boolean onTouchEvent(MotionEvent event){
        if(bitmap==null)return true;
        int action=event.getActionMasked();
        if(action==MotionEvent.ACTION_DOWN){dismissTouch=listener.dismissMenus();pinched=false;turned=false;downX=lastX=event.getX();downY=lastY=event.getY();}
        if(dismissTouch){if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL)dismissTouch=false;return true;}
        scales.onTouchEvent(event);gestures.onTouchEvent(event);
        if(action==MotionEvent.ACTION_MOVE&&!scales.isInProgress()){
            if(zoom>1)dx+=event.getX()-lastX;
            top+=event.getY()-lastY;clamp();
            if(!pinched&&Math.abs(event.getY()-downY)>UiKit.dp(getContext(),8)&&Math.abs(event.getY()-downY)>Math.abs(event.getX()-downX))anchor=Math.max(0,Math.min(1,-top/(bitmap.getHeight()*scale())));
            invalidate();
        }
        lastX=event.getX();lastY=event.getY();if(action==MotionEvent.ACTION_UP){turn(event.getX()-downX,event.getY()-downY);if(!pinched&&zoom==1&&Math.abs(event.getY()-downY)>UiKit.dp(getContext(),8)&&Math.abs(event.getY()-downY)>Math.abs(event.getX()-downX))listener.moved(anchor);performClick();}return true;
    }
    private boolean turn(float x,float y){
        if(turned||pinched||zoom>1||Math.abs(x)<UiKit.dp(getContext(),72)||Math.abs(x)<Math.abs(y)*1.5f)return false;
        turned=true;listener.turn(x<0?1:-1);return true;
    }
    @Override public boolean performClick(){super.performClick();return true;}
}
