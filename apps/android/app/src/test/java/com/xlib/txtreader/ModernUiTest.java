package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.drawable.GradientDrawable;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.TextView;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk={23,35},qualifiers="w320dp-h480dp")
public class ModernUiTest {
    private ActivityController<Activity> controller;
    private Activity activity;
    private AlertDialog dialog;
    @Before public void setup(){controller=Robolectric.buildActivity(Activity.class).setup();activity=controller.get();}
    @After public void cleanup(){if(dialog!=null)dialog.dismiss();controller.pause().stop().destroy();}
    private void idle(){Shadows.shadowOf(Looper.getMainLooper()).idle();}
    @Test public void dialogsUseAppThemeRoundedSurfaceAndAccessibleActionsInBothThemes(){
        for(boolean dark:new boolean[]{false,true}){
            dialog=AppDialogs.builder(activity,dark).setTitle("阅读设置").setMessage("正文和设置使用同一套配色").setPositiveButton("完成",null).setNegativeButton("取消",null).show();idle();
            assertTrue(dialog.getWindow().getDecorView().getBackground() instanceof GradientDrawable);
            if(android.os.Build.VERSION.SDK_INT>=24)assertEquals(UiKit.dp(activity,28),((GradientDrawable)dialog.getWindow().getDecorView().getBackground()).getCornerRadius(),.01f);
            assertEquals(dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT,((TextView)dialog.findViewById(android.R.id.message)).getCurrentTextColor());
            assertTrue(dialog.getButton(-1).getMinimumHeight()>=UiKit.dp(activity,48));
            assertTrue(dialog.getWindow().getAttributes().width<=UiKit.dp(activity,560));dialog.dismiss();
        }
    }
    @Test public void stylingPreservesValidationAndUserInstalledOnShowListener(){
        EditText input=new EditText(activity);input.setSingleLine(true);
        dialog=AppDialogs.builder(activity,true).setTitle("前往页码").setView(input).setPositiveButton("前往",null).setNegativeButton("取消",null).create();
        dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->input.setError("请输入页码")));
        dialog.show();idle();dialog.getButton(-1).performClick();assertTrue(dialog.isShowing());assertNotNull(input.getError());assertEquals(UiKit.DARK_TEXT,input.getCurrentTextColor());assertEquals(UiKit.dp(activity,24),((View)input.getParent()).getPaddingLeft());assertEquals(UiKit.dp(activity,24),((View)input.getParent()).getPaddingRight());
    }
    @Test public void longThreeActionDialogStacksButtonsInsteadOfTruncating(){
        dialog=AppDialogs.builder(activity,false).setTitle("阅读进度同步").setMessage("选择操作")
            .setPositiveButton("重新启用此书的同步",null).setNeutralButton("删除本书云端进度",null).setNegativeButton("关闭此窗口",null).show();idle();
        assertEquals(LinearLayout.VERTICAL,((LinearLayout)dialog.getButton(-1).getParent()).getOrientation());
        for(int id:new int[]{-1,-2,-3})assertEquals(ViewGroup.LayoutParams.MATCH_PARENT,dialog.getButton(id).getLayoutParams().width);
    }
    @Test public void narrowToolbarWrapsWithoutClippingOrOverlappingTargets(){
        LinearLayout toolbar=ReaderChrome.menu(activity,false,true);toolbar.setVisibility(View.VISIBLE);
        for(int i=0;i<7;i++){ImageButton icon=ReaderChrome.icon(activity,false,R.drawable.ic_settings,"操作 "+i,()->{});toolbar.addView(icon,new LinearLayout.LayoutParams(UiKit.dp(activity,48),UiKit.dp(activity,48)));}
        int width=UiKit.dp(activity,288);toolbar.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));toolbar.layout(0,0,width,toolbar.getMeasuredHeight());
        assertTrue(toolbar.getMeasuredHeight()>UiKit.dp(activity,96));
        for(int i=0;i<toolbar.getChildCount();i++){View a=toolbar.getChildAt(i);assertTrue(a.getWidth()>=UiKit.dp(activity,48));assertTrue(a.getHeight()>=UiKit.dp(activity,48));assertTrue(a.getLeft()>=0&&a.getRight()<=width);for(int j=0;j<i;j++){View b=toolbar.getChildAt(j);assertFalse(android.graphics.Rect.intersects(new android.graphics.Rect(a.getLeft(),a.getTop(),a.getRight(),a.getBottom()),new android.graphics.Rect(b.getLeft(),b.getTop(),b.getRight(),b.getBottom())));}}
    }
    @Test public void dialogActionsStayAtLogicalEndAfterWrapping(){
        AdaptiveRow actions=new AdaptiveRow(activity);actions.setGravity(android.view.Gravity.END);
        Button cancel=new Button(activity),confirm=new Button(activity);cancel.setText("取消");confirm.setText("保存");
        actions.addView(cancel,new LinearLayout.LayoutParams(UiKit.dp(activity,64),UiKit.dp(activity,48)));actions.addView(confirm,new LinearLayout.LayoutParams(UiKit.dp(activity,64),UiKit.dp(activity,48)));
        int width=UiKit.dp(activity,260);actions.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));actions.layout(0,0,width,actions.getMeasuredHeight());assertEquals(width,confirm.getRight());assertTrue(cancel.getLeft()>0);
        actions.setGravity(android.view.Gravity.START);actions.requestLayout();actions.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));actions.layout(0,0,width,actions.getMeasuredHeight());assertEquals(0,cancel.getLeft());
    }
    @Test @Config(qualifiers="w840dp-h360dp") public void longCustomPanelsFitShortWideWindows(){
        android.app.Dialog panel=new android.app.Dialog(activity);LinearLayout card=new LinearLayout(activity);card.setOrientation(LinearLayout.VERTICAL);
        for(int i=0;i<40;i++){TextView row=new TextView(activity);row.setText("阅读设置选项 "+i);row.setMinHeight(UiKit.dp(activity,48));card.addView(row);}
        AppDialogs.customContent(panel,card);AppDialogs.showCustom(panel);idle();
        try{assertTrue(panel.getWindow().getAttributes().width<=UiKit.dp(activity,560));View root=((ViewGroup)panel.findViewById(android.R.id.content)).getChildAt(0);assertTrue(root.getMeasuredHeight()<=activity.getResources().getDisplayMetrics().heightPixels*.81f);assertTrue(root instanceof android.widget.ScrollView);}finally{panel.dismiss();}
    }
    @Test public void themeRestylingDoesNotEnableUnavailableReaderActions(){
        ImageButton search=ReaderChrome.icon(activity,false,R.drawable.ic_search,"搜索",()->fail("Disabled action executed"));ReaderChrome.enabled(search,false);
        UiKit.styleIconButton(activity,search,UiKit.DARK_TEXT,UiKit.DARK_SURFACE_VARIANT,16);
        assertFalse(search.isEnabled());assertEquals(.35f,search.getAlpha(),0f);
    }
}
