package com.xlib.txtreader;

import android.content.Context;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;

/** Shared reading surface and floating menu containers; content belongs to its format. */
final class ReaderChrome extends FrameLayout {
    ReaderChrome(Context context, int background) { super(context); setBackgroundColor(background); }

    static LinearLayout menu(Context context, boolean dark, boolean top) {
        LinearLayout menu = top ? new AdaptiveRow(context) : new LinearLayout(context);
        menu.setOrientation(top ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        menu.setGravity(Gravity.CENTER_VERTICAL);
        menu.setPadding(dp(context, top ? 8 : 10), dp(context, top ? 7 : 8),
                dp(context, top ? 8 : 10), dp(context, top ? 7 : 10));
        UiKit.styleCard(context, menu, dark ? UiKit.DARK_SURFACE : UiKit.LIGHT_SURFACE, top ? 22 : 24, top ? 8 : 10);
        menu.setClickable(true); menu.setVisibility(View.GONE);
        return menu;
    }

    static ImageButton icon(Context context, boolean dark, int drawable, String description, Runnable action) {
        ImageButton button = new ImageButton(context); button.setImageResource(drawable);
        button.setContentDescription(description);
        UiKit.styleIconButton(context, button, dark ? UiKit.DARK_TEXT : UiKit.LIGHT_TEXT,
                dark ? UiKit.DARK_SURFACE_VARIANT : UiKit.LIGHT_SURFACE_VARIANT, 14);
        button.setOnClickListener(v -> action.run()); return button;
    }
    static void enabled(View view, boolean enabled) {
        view.setEnabled(enabled);
        view.setAlpha(enabled ? 1f : .35f);
    }
    private static int dp(Context context, int value) { return UiKit.dp(context, value); }
}
