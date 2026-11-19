package com.xlib.txtreader;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CancellationException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Fixed-origin, non-overlapping, resumable search. The provider owns source coordinates. */
final class DocumentSearch {
    interface Cancellation { boolean isCancelled(); }
    interface Source {
        int units();
        String text(int unit) throws Exception;
        DocumentLocator locator(int unit, int offset) throws Exception;
        default String text(int unit, Cancellation cancelled) throws Exception { return text(unit); }
        default DocumentLocator locator(int unit, int offset, Cancellation cancelled) throws Exception { return locator(unit, offset); }
    }
    static final class Hit {
        final DocumentLocator locator;
        final String snippet;
        final int start,end;
        Hit(DocumentLocator locator, String snippet, int start, int end) { this.locator = locator; this.snippet = snippet; this.start=start; this.end=end; }
    }
    private volatile boolean cancelled;
    void cancel(){cancelled=true;}
    private boolean isCancelled() { return cancelled || Thread.currentThread().isInterrupted(); }
    private void checkCancelled() throws InterruptedException { if (isCancelled()) throw new InterruptedException(); }
    final String query;
    private final Pattern pattern;
    final int originUnit, originOffset;
    int unit, offset;
    boolean wrapped, needsWrap, complete;
    DocumentSearch(String input, int originUnit, int originOffset) {
        query = SearchTextRules.normalize(input);
        int count = SearchTextRules.characterCount(query);
        if (count < 2 || count > 32) throw new IllegalArgumentException("请输入 2–32 个字符");
        pattern = SearchTextRules.pattern(query);
        this.originUnit = unit = originUnit; this.originOffset = offset = originOffset;
    }
    boolean wrap() {
        if (!needsWrap) return false;
        needsWrap = false; wrapped = true; unit = offset = 0; return true;
    }
    List<Hit> next(Source source) throws Exception {
        List<Hit> result = new ArrayList<>();
        checkCancelled();
        if (complete || needsWrap) return result;
        try {
            while (unit < source.units()) {
                checkCancelled();
                if (wrapped && unit > originUnit) { complete = true; return result; }
                String text = source.text(unit, this::isCancelled);
                checkCancelled();
                int boundary = wrapped && unit == originUnit ? Math.min(originOffset, text.length()) : text.length();
                Matcher matcher = pattern.matcher(text);
                matcher.region(Math.min(offset, boundary), boundary);
                while (matcher.find()) {
                    checkCancelled();
                    int start = matcher.start(), end = matcher.end();
                    DocumentLocator locator = source.locator(unit, start, this::isCancelled);
                    checkCancelled();
                    result.add(new Hit(locator, text.substring(ReaderTextSelection.boundary(text,Math.max(0,start-30)), ReaderTextSelection.nextBoundary(text,Math.min(text.length(),end+30))),start,end));
                    offset = end;
                    if (result.size() == 200) return result;
                }
                if (wrapped && unit == originUnit) { complete = true; return result; }
                unit++; offset = 0;
            }
            if (wrapped || (originUnit == 0 && originOffset == 0)) complete = true;
            else needsWrap = true;
            return result;
        } catch (CancellationException cancelledExtraction) {
            if (isCancelled()) throw new InterruptedException();
            throw cancelledExtraction;
        }
    }
}
