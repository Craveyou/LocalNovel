package com.xlib.txtreader;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.view.Gravity;
import android.widget.LinearLayout;
import java.util.ArrayList;
import java.util.List;

/** Wraps toolbar controls on narrow windows and at large font sizes without shrinking targets. */
final class AdaptiveRow extends LinearLayout {
    private final List<List<View>> rows=new ArrayList<>();
    private int rowGravity=Gravity.START|Gravity.TOP;
    @Override public void setGravity(int gravity){super.setGravity(gravity);rowGravity=gravity;}
    AdaptiveRow(Context context){super(context);setOrientation(HORIZONTAL);}
    @Override protected void onMeasure(int widthSpec,int heightSpec){
        rows.clear();int width=MeasureSpec.getSize(widthSpec),available=Math.max(1,width-getPaddingLeft()-getPaddingRight());
        List<View> row=new ArrayList<>();rows.add(row);int used=0;
        for(int i=0;i<getChildCount();i++){
            View child=getChildAt(i);if(child.getVisibility()==GONE)continue;
            LayoutParams lp=(LayoutParams)child.getLayoutParams();
            int w=lp.width>0?MeasureSpec.makeMeasureSpec(lp.width,MeasureSpec.EXACTLY):MeasureSpec.makeMeasureSpec(available,MeasureSpec.AT_MOST);
            int h=MeasureSpec.makeMeasureSpec(0,MeasureSpec.UNSPECIFIED);
            child.measure(w,h);if(lp.height>0&&child.getMeasuredHeight()<lp.height)child.measure(w,MeasureSpec.makeMeasureSpec(lp.height,MeasureSpec.EXACTLY));int extent=child.getMeasuredWidth()+lp.leftMargin+lp.rightMargin;
            if(!row.isEmpty()&&used+extent>available){row=new ArrayList<>();rows.add(row);used=0;}
            row.add(child);used+=extent;
        }
        int height=getPaddingTop()+getPaddingBottom();
        for(List<View> line:rows){
            int total=0,rowHeight=0;float weight=0;
            for(View child:line){LayoutParams lp=(LayoutParams)child.getLayoutParams();total+=child.getMeasuredWidth()+lp.leftMargin+lp.rightMargin;weight+=lp.weight;}
            for(View child:line){LayoutParams lp=(LayoutParams)child.getLayoutParams();if(lp.weight>0&&weight>0&&total<available)child.measure(MeasureSpec.makeMeasureSpec(child.getMeasuredWidth()+(int)((available-total)*lp.weight/weight),MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(child.getMeasuredHeight(),MeasureSpec.EXACTLY));rowHeight=Math.max(rowHeight,child.getMeasuredHeight()+lp.topMargin+lp.bottomMargin);}
            height+=rowHeight;
        }
        height+=Math.max(0,rows.size()-1)*UiKit.dp(getContext(),8);
        setMeasuredDimension(resolveSize(width,widthSpec),resolveSize(height,heightSpec));
    }
    @Override protected void onLayout(boolean changed,int l,int t,int r,int b){
        int y=getPaddingTop();boolean rtl=getLayoutDirection()==LAYOUT_DIRECTION_RTL;
        for(List<View> row:rows){int extent=0,height=0;
            for(View child:row){LayoutParams lp=(LayoutParams)child.getLayoutParams();extent+=child.getMeasuredWidth()+lp.leftMargin+lp.rightMargin;height=Math.max(height,child.getMeasuredHeight()+lp.topMargin+lp.bottomMargin);}
            int available=getWidth()-getPaddingLeft()-getPaddingRight(),absolute=Gravity.getAbsoluteGravity(rowGravity,getLayoutDirection())&Gravity.HORIZONTAL_GRAVITY_MASK;
            int offset=absolute==Gravity.RIGHT?available-extent:absolute==Gravity.CENTER_HORIZONTAL?(available-extent)/2:0;
            int x=rtl?getPaddingLeft()+offset+extent:getPaddingLeft()+offset;
            for(View child:row){LayoutParams lp=(LayoutParams)child.getLayoutParams();int w=child.getMeasuredWidth(),h=child.getMeasuredHeight();int top=y+lp.topMargin;
                if((rowGravity&Gravity.VERTICAL_GRAVITY_MASK)==Gravity.CENTER_VERTICAL)top+=(height-h-lp.topMargin-lp.bottomMargin)/2;
                if(rtl){x-=lp.rightMargin;child.layout(x-w,top,x,top+h);x-=w+lp.leftMargin;}else{x+=lp.leftMargin;child.layout(x,top,x+w,top+h);x+=w+lp.rightMargin;}}
            y+=height+UiKit.dp(getContext(),8);
        }
    }
}
