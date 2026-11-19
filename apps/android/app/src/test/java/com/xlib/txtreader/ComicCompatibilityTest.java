package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.app.Activity;
import android.content.Context;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class) @Config(sdk={23,35})
public class ComicCompatibilityTest {
    private View find(View view,String label){if(view instanceof Button&&label.contentEquals(((Button)view).getText()))return view;if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++){View found=find(((ViewGroup)view).getChildAt(i),label);if(found!=null)return found;}return null;}
    @Test public void themedCardsOperateAtMinimumSdkAndDirectionUsesTheExistingDatabase()throws Exception {
        Context context=RuntimeEnvironment.getApplication();
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){ReadingPreferences preferences=new ReadingPreferences(db);assertFalse(preferences.comicRightToLeft());preferences.setComicRightToLeft(true);assertTrue(preferences.comicRightToLeft());}
        try(LocalDatabase db=LocalDatabase.open(context,context.getSharedPreferences("xlib_reader",0))){assertTrue(new ReadingPreferences(db).comicRightToLeft());new ReadingPreferences(db).setComicRightToLeft(false);}
        ActivityController<Activity> controller=Robolectric.buildActivity(Activity.class).setup();int[] selected={-1};
        try{ReaderDialogs.choose(controller.get(),true,"添加书籍",new String[]{"导入书籍","漫画预览"},index->selected[0]=index);Shadows.shadowOf(Looper.getMainLooper()).idle();android.app.Dialog dialog=org.robolectric.shadows.ShadowDialog.getLatestDialog();assertTrue(dialog.isShowing());View option=find(dialog.getWindow().getDecorView(),"漫画预览");assertNotNull(option);option.performClick();assertEquals(1,selected[0]);assertFalse(dialog.isShowing());}finally{controller.pause().stop().destroy();}
    }
}
