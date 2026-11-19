package com.xlib.txtreader;

import android.content.Context;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import java.util.Locale;

/** Changes are immediate; closing the panel keeps this process's display settings. */
final class PdfCropControls extends LinearLayout {
    interface Listener { void changed(PdfCropSettings settings); }
    private final CheckBox enabled;
    private final SeekBar left, right;
    private final TextView leftLabel, rightLabel;
    private final Listener listener;
    private boolean binding;

    PdfCropControls(Context context, boolean dark, Listener listener) {
        super(context); this.listener = listener;
        setOrientation(VERTICAL);
        int padding = UiKit.dp(context, 16);
        setPadding(0, padding / 2, 0, padding / 2);
        int color = dark ? UiKit.DARK_TEXT : UiKit.LIGHT_TEXT;
        setBackgroundColor(dark ? UiKit.DARK_SURFACE : UiKit.LIGHT_SURFACE);
        enabled = new CheckBox(context); enabled.setText("启用裁边"); enabled.setTextColor(color); addView(enabled);
        leftLabel = label(context, color); addView(leftLabel);
        left = slider(context, dark, "左侧裁边百分比"); addView(left, new LayoutParams(-1, UiKit.dp(context, 48)));
        rightLabel = label(context, color); addView(rightLabel);
        right = slider(context, dark, "右侧裁边百分比"); addView(right, new LayoutParams(-1, UiKit.dp(context, 48)));
        TextView note = label(context, color);
        note.setText("拖动比例即启用，页面实时预览。本次运行内所有 PDF 共用，重启后关闭。");
        addView(note);
        bind(PdfCropSettings.current());
        enabled.setOnCheckedChangeListener((button, checked) -> publish());
        SeekBar.OnSeekBarChangeListener changes = new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar bar, int progress, boolean user) { if(user&&!enabled.isChecked())enabled.setChecked(true);publish(); }
            public void onStartTrackingTouch(SeekBar bar) { if(!enabled.isChecked())enabled.setChecked(true);bar.getParent().requestDisallowInterceptTouchEvent(true); }
            public void onStopTrackingTouch(SeekBar bar) { }
        };
        left.setOnSeekBarChangeListener(changes); right.setOnSeekBarChangeListener(changes);
    }

    private static TextView label(Context context, int color) {
        TextView label = new TextView(context); label.setTextColor(color); return label;
    }
    private static SeekBar slider(Context context, boolean dark, String description) {
        SeekBar bar = new SeekBar(context); bar.setMax(30); bar.setContentDescription(description);
        bar.setMinimumHeight(UiKit.dp(context, 48)); UiKit.styleReaderSeekBar(context, bar, dark); return bar;
    }
    private void bind(PdfCropSettings value) {
        binding = true;
        enabled.setChecked(value.enabled); left.setProgress(value.leftPercent); right.setProgress(value.rightPercent);
        binding = false; updateLabels();
    }
    private void updateLabels() {
        leftLabel.setText(String.format(Locale.getDefault(), "左侧裁去 %d%%", left.getProgress()));
        rightLabel.setText(String.format(Locale.getDefault(), "右侧裁去 %d%%", right.getProgress()));
        // Sliders remain usable while off: dragging enables cropping automatically.
    }
    private void publish() {
        if (binding) return;
        updateLabels();
        PdfCropSettings settings = new PdfCropSettings(enabled.isChecked(), left.getProgress(), right.getProgress());
        PdfCropSettings.setCurrent(settings); listener.changed(settings);
    }
    void reset() { bind(PdfCropSettings.defaults()); publish(); }
}
