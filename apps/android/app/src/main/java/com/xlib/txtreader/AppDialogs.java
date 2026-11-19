package com.xlib.txtreader;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.view.Gravity;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.CompoundButton;
import android.content.res.ColorStateList;

/** App-themed dialog surfaces; keeps platform validation, cancellation and accessibility behavior. */
final class AppDialogs {
    private AppDialogs() { }
    static AlertDialog.Builder builder(Context context, boolean dark) {
        return new AlertDialog.Builder(context,dark?R.style.XlibDialogDark:R.style.XlibDialogLight) {
            @Override public AlertDialog.Builder setView(View content) {
                int inset=UiKit.dp(context,24);
                FrameLayout frame=new FrameLayout(context);
                frame.setPadding(inset,0,inset,0);
                frame.addView(content,new FrameLayout.LayoutParams(-1,-2));
                return super.setView(frame);
            }
            @Override public AlertDialog create() {
                AlertDialog dialog=super.create();
                // Install AlertController's features before obtaining decor (required on API 23).
                dialog.create();
                // An attach callback leaves callers free to install their own onShow validation.
                View decor=dialog.getWindow().getDecorView();
                decor.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){
                    public void onViewAttachedToWindow(View view){view.post(()->{if(dialog.isShowing())style(dialog,dark);});}
                    public void onViewDetachedFromWindow(View view){}
                });
                return dialog;
            }
        };
    }
    static int width(Context context) {
        return Math.min(UiKit.dp(context,560),Math.max(1,context.getResources().getDisplayMetrics().widthPixels-UiKit.dp(context,48)));
    }
    static void window(Dialog dialog) {
        Window window=dialog.getWindow();if(window==null)return;
        window.setLayout(width(dialog.getContext()),ViewGroup.LayoutParams.WRAP_CONTENT);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);window.setDimAmount(window.getAttributes().gravity==Gravity.BOTTOM?0f:.32f);
    }
    static ScrollView viewport(Context context,View content) {
        ScrollView viewport=new ScrollView(context){
            @Override protected void onMeasure(int w,int h){
                int max=(int)(getResources().getDisplayMetrics().heightPixels*.80f);
                int bound=View.MeasureSpec.getMode(h)==View.MeasureSpec.UNSPECIFIED?max:Math.min(max,View.MeasureSpec.getSize(h));
                super.onMeasure(w,View.MeasureSpec.makeMeasureSpec(bound,View.MeasureSpec.AT_MOST));
            }
        };
        viewport.setFillViewport(false);
        if(content.getBackground()!=null&&content.getBackground().getConstantState()!=null)viewport.setBackground(content.getBackground().getConstantState().newDrawable());
        viewport.setClipToOutline(true);viewport.addView(content);return viewport;
    }
    static void customContent(Dialog dialog,View card) {
        dialog.setContentView(viewport(dialog.getContext(),card));
        if(dialog.isShowing())window(dialog);
    }
    static void showCustom(Dialog dialog) {
        dialog.show();dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));window(dialog);
    }
    static void style(AlertDialog dialog,boolean dark) {
        Context context=dialog.getContext();Window window=dialog.getWindow();if(window==null)return;
        window.setBackgroundDrawable(UiKit.rounded(context,dark?UiKit.DARK_SURFACE:UiKit.LIGHT_SURFACE,UiKit.DIALOG_RADIUS));
        window(dialog);
        View decor=window.getDecorView();styleContent(decor,dark);
        ListView list=dialog.getListView();
        if(list!=null){list.setDivider(null);list.setSelector(UiKit.interactive(context,Color.TRANSPARENT,12,UiKit.withAlpha(dark?UiKit.DARK_ACCENT:UiKit.LIGHT_ACCENT,30)));list.setOnHierarchyChangeListener(new ViewGroup.OnHierarchyChangeListener(){public void onChildViewAdded(View parent,View child){styleContent(child,dark);}public void onChildViewRemoved(View parent,View child){}});}
        for(int which:new int[]{AlertDialog.BUTTON_NEGATIVE,AlertDialog.BUTTON_NEUTRAL,AlertDialog.BUTTON_POSITIVE}){
            Button button=dialog.getButton(which);if(button==null)continue;
            UiKit.styleButton(context,button,which==AlertDialog.BUTTON_POSITIVE?(dark?UiKit.DARK_ACCENT_CONTAINER:UiKit.LIGHT_ACCENT_CONTAINER):Color.TRANSPARENT,dark?UiKit.DARK_ACCENT:UiKit.LIGHT_ACCENT,UiKit.CONTROL_RADIUS);
            button.setTextSize(14);button.setPadding(UiKit.dp(context,16),0,UiKit.dp(context,16),0);
        }
        Button positive=dialog.getButton(AlertDialog.BUTTON_POSITIVE);
        if(positive!=null&&positive.getParent() instanceof LinearLayout){
            LinearLayout bar=(LinearLayout)positive.getParent();int needed=0,actions=0;
            for(int i=0;i<bar.getChildCount();i++)if(bar.getChildAt(i) instanceof Button&&bar.getChildAt(i).getVisibility()!=View.GONE){actions++;Button b=(Button)bar.getChildAt(i);needed+=Math.max(UiKit.dp(context,48),(int)Math.ceil(b.getPaint().measureText(b.getText().toString()))+b.getPaddingLeft()+b.getPaddingRight())+UiKit.dp(context,8);}
            if(actions>2||needed>width(context)-UiKit.dp(context,48)){
                bar.setOrientation(LinearLayout.VERTICAL);
                for(int i=0;i<bar.getChildCount();i++){View child=bar.getChildAt(i);if(!(child instanceof Button)){child.setVisibility(View.GONE);continue;}LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.topMargin=UiKit.dp(context,4);child.setLayoutParams(lp);}
            }
        }
    }
    private static void styleContent(View view,boolean dark) {
        Context context=view.getContext();int foreground=dark?UiKit.DARK_TEXT:UiKit.LIGHT_TEXT;
        if(view instanceof EditText){UiKit.styleInput(context,(EditText)view,dark);}
        else if(view instanceof CompoundButton){CompoundButton toggle=(CompoundButton)view;toggle.setTextColor(foreground);toggle.setMinHeight(UiKit.dp(context,48));toggle.setButtonTintList(ColorStateList.valueOf(dark?UiKit.DARK_ACCENT:UiKit.LIGHT_ACCENT));}
        else if(view instanceof Button){Button button=(Button)view;UiKit.styleButton(context,button,Color.TRANSPARENT,foreground,UiKit.CONTROL_RADIUS);}
        else if(view instanceof TextView){TextView text=(TextView)view;text.setTextColor(foreground);if(view.getId()==context.getResources().getIdentifier("alertTitle","id","android"))UiKit.styleTitle(text,foreground,22);if(view.getId()==android.R.id.message){text.setTextSize(16);text.setLineSpacing(UiKit.dp(context,3),1);}if(view.getParent() instanceof ListView){text.setTextSize(16);text.setMinHeight(UiKit.dp(context,56));text.setPadding(UiKit.dp(context,24),UiKit.dp(context,12),UiKit.dp(context,24),UiKit.dp(context,12));}}
        if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)styleContent(((ViewGroup)view).getChildAt(i),dark);
    }
}
