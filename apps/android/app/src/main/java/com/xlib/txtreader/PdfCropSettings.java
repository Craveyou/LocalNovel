package com.xlib.txtreader;

/** Process-only display preferences. Never written to book metadata or persistent settings. */
final class PdfCropSettings {
    private static PdfCropSettings current = defaults();
    final boolean enabled;
    final int leftPercent, rightPercent;

    PdfCropSettings(boolean enabled, int leftPercent, int rightPercent) {
        this.enabled = enabled;
        this.leftPercent = Math.max(0, Math.min(30, leftPercent));
        this.rightPercent = Math.max(0, Math.min(30, rightPercent));
    }

    static PdfCropSettings defaults() { return new PdfCropSettings(false, 10, 10); }
    static PdfCropSettings current() { return current; }
    static void setCurrent(PdfCropSettings value) { current = value; }
    static void reset() { current = defaults(); }

    float leftFraction() { return enabled ? leftPercent / 100f : 0; }
    float rightFraction() { return enabled ? rightPercent / 100f : 0; }

    @Override public boolean equals(Object other) {
        if (!(other instanceof PdfCropSettings)) return false;
        PdfCropSettings value = (PdfCropSettings) other;
        return enabled == value.enabled && leftPercent == value.leftPercent && rightPercent == value.rightPercent;
    }
    @Override public int hashCode() { return (enabled ? 1 : 0) * 961 + leftPercent * 31 + rightPercent; }
}
