package com.xlib.txtreader;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Matches the current TXT/library confirmation cards, including narrow/landscape viewports. */
final class ReaderDialogs {
    interface Choice { void selected(int index); }
    private ReaderDialogs() { }
    static void choose(Context context,boolean dark,String title,String[] labels,Choice action) {
        Panel panel=new Panel(context,dark,title);
        for(int i=0;i<labels.length;i++){final int index=i;Button option=panel.button(labels[i],false);option.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);option.setOnClickListener(v->{panel.dialog.dismiss();action.selected(index);});panel.body.addView(option,new LinearLayout.LayoutParams(-1,-2));}
        panel.action("取消",false,()->panel.dialog.dismiss());panel.show();
    }
    static void message(Context context,boolean dark,String title,String message,Runnable done) {
        Panel panel=new Panel(context,dark,title);panel.message(message);panel.action(done==null?"知道了":"返回书架",true,()->{panel.dialog.dismiss();if(done!=null)done.run();});
        if(done!=null)panel.dialog.setOnCancelListener(d->done.run());panel.show();
    }
    static void jump(Context context,boolean dark,int page,int count,Choice chosen) {
        Panel panel=new Panel(context,dark,"跳页");EditText field=new EditText(context);UiKit.styleInput(context,field,dark);field.setContentDescription("页码");field.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);field.setHint("1–"+count);field.setText(String.valueOf(page+1));field.setSelectAllOnFocus(true);field.setTextColor(panel.foreground);field.setHintTextColor(panel.muted);field.setSingleLine(true);
        panel.body.addView(field,new LinearLayout.LayoutParams(-1,dp(context,56)));panel.action("取消",false,()->panel.dialog.dismiss());
        panel.action("前往",true,()->{try{int target=Integer.parseInt(field.getText().toString().trim())-1;if(target<0||target>=count)throw new NumberFormatException();panel.dialog.dismiss();chosen.selected(target);}catch(NumberFormatException error){field.setError("请输入 1–"+count+" 的页码");}});panel.show();
    }
    private static final class Panel {
        final Context context;final boolean dark;final int foreground,muted;
        final Dialog dialog;final LinearLayout body,actions,card;
        Panel(Context context,boolean dark,String title) {
            this.context=context;this.dark=dark;foreground=dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT;muted=dark?UiKit.DARK_MUTED:UiKit.LIGHT_MUTED;
            dialog=new Dialog(context);dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
            card=new LinearLayout(context);card.setOrientation(LinearLayout.VERTICAL);card.setPadding(dp(context,22),dp(context,20),dp(context,22),dp(context,14));UiKit.styleCard(context,card,dark?UiKit.DARK_SURFACE:UiKit.LIGHT_SURFACE,UiKit.DIALOG_RADIUS,8);
            TextView heading=new TextView(context);UiKit.styleTitle(heading,foreground,22);heading.setText(title);heading.setPadding(0,0,0,dp(context,12));card.addView(heading);
            body=new LinearLayout(context);body.setOrientation(LinearLayout.VERTICAL);card.addView(body);
            actions=new AdaptiveRow(context);actions.setGravity(Gravity.END|Gravity.CENTER_VERTICAL);actions.setPadding(0,dp(context,12),0,0);card.addView(actions);
            AppDialogs.customContent(dialog,card);
        }
        void message(String text){TextView view=new TextView(context);view.setText(text);view.setTextColor(muted);view.setTextSize(14);view.setLineSpacing(dp(context,3),1);body.addView(view);}
        Button button(String title,boolean primary){Button button=new Button(context);button.setText(title);button.setTextSize(14);UiKit.styleButton(context,button,primary?(dark?UiKit.DARK_ACCENT_CONTAINER:UiKit.LIGHT_ACCENT_CONTAINER):Color.TRANSPARENT,primary?(dark?UiKit.DARK_ACCENT:UiKit.LIGHT_ACCENT):foreground,14);return button;}
        void action(String title,boolean primary,Runnable callback){Button button=button(title,primary);button.setOnClickListener(v->callback.run());LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-2,dp(context,48));lp.leftMargin=dp(context,6);actions.addView(button,lp);}
        void show(){AppDialogs.showCustom(dialog);}
    }
    private static int dp(Context context,int value){return UiKit.dp(context,value);}
}
