package com.xlib.txtreader;

import static org.junit.Assert.*;
import org.junit.Test;
import org.json.JSONObject;
import java.util.List;

public class DocumentCoreTest {
    @Test public void typedLocationsRoundTripAndRejectUnknownOrOutOfRange() throws Exception {
        DocumentLocator pdf = DocumentLocator.pdf(2, 4, 0.5);
        assertEquals(0.625, pdf.progress(), 0.00001);
        assertEquals(pdf, DocumentLocator.fromJson(pdf.json()));
        assertThrows(IllegalArgumentException.class,()->DocumentLocator.fromJson(new JSONObject("{\"format\":\"pdf\",\"version\":1,\"page\":0.5,\"pageCount\":4,\"y\":0}")));
        assertThrows(IllegalArgumentException.class,()->DocumentLocator.fromJson(new JSONObject("{\"format\":\"pdf\",\"version\":1,\"page\":4294967296,\"pageCount\":4,\"y\":0}")));
        assertThrows(IllegalArgumentException.class,()->DocumentLocator.fromJson(pdf.json().put("text","forbidden")));
        DocumentLocator epub = DocumentLocator.epub("OEBPS/chapter.xhtml", 1, 3, 30, 60);
        assertEquals(0.5, epub.progress(), 0.00001);
        assertEquals(epub, DocumentLocator.fromJson(epub.json()));
        assertThrows(IllegalArgumentException.class, () -> DocumentLocator.pdf(4, 4, 0));
        assertThrows(IllegalArgumentException.class, () -> DocumentLocator.pdf(0, 1, Double.NaN));
        assertThrows(IllegalArgumentException.class, () -> DocumentLocator.epub("../private", 0, 1, 0, 1));
        assertThrows(IllegalArgumentException.class, () -> DocumentLocator.epub("a.xhtml", 0, 1, 2, 1));
        assertThrows(IllegalArgumentException.class, () -> DocumentLocator.fromJson(new JSONObject("{\"format\":\"pdf\",\"version\":2}")));
    }

    @Test public void searchContinuesPast200WithoutDuplicatesAndWrapsOnlyOnRequest() throws Exception {
        String text = "Hello ".repeat(450);
        DocumentSearch.Source source = new DocumentSearch.Source() {
            public int units() { return 1; }
            public String text(int unit) { return text; }
            public DocumentLocator locator(int unit, int offset) { return DocumentLocator.epub("a.xhtml", 0, 1, offset, text.length()); }
        };
        DocumentSearch search = new DocumentSearch("hello", 0, 600);
        assertEquals(200, search.next(source).size());
        List<DocumentSearch.Hit> second = search.next(source);
        assertEquals(150, second.size()); assertTrue(search.needsWrap); assertFalse(search.complete);
        assertTrue(search.next(source).isEmpty()); assertTrue(search.wrap());
        List<DocumentSearch.Hit> first = search.next(source);
        assertEquals(100, first.size()); assertTrue(search.complete);
        assertEquals(0, first.get(0).locator.textOffset);
        assertEquals(1800, second.get(0).locator.textOffset);
    }

    @Test public void nonOverlappingSearchAndGraphemeQueryLimitsRemainShared() throws Exception {
        DocumentSearch.Source source = new DocumentSearch.Source() {
            public int units() { return 1; }
            public String text(int unit) { return "aaaaa"; }
            public DocumentLocator locator(int unit, int offset) { return DocumentLocator.pdf(0, 1, offset / 5d); }
        };
        assertEquals(2, new DocumentSearch("aa", 0, 0).next(source).size());
        assertThrows(IllegalArgumentException.class, () -> new DocumentSearch("👩‍💻", 0, 0));
        assertThrows(IllegalArgumentException.class, () -> new DocumentSearch("x".repeat(33), 0, 0));
        new DocumentSearch("👩‍💻你好", 0, 0);
    }

    @Test public void cancellationDuringTextExtractionDoesNotLocateHitsOrFinishTheRange() throws Exception {
        DocumentSearch search = new DocumentSearch("hello", 0, 0);
        DocumentSearch.Source source = new DocumentSearch.Source() {
            public int units() { return 1; }
            public String text(int unit) { search.cancel(); return "hello hello"; }
            public DocumentLocator locator(int unit, int offset) { throw new AssertionError("Cancelled extraction must not locate results"); }
        };
        assertThrows(InterruptedException.class, () -> search.next(source));
        assertFalse(search.complete); assertFalse(search.needsWrap);
        assertEquals(0, search.offset);
    }

    @Test public void cancellationWithinOneDensePageDoesNotBuildTheRestOfTheBatch() throws Exception {
        DocumentSearch search = new DocumentSearch("hello", 0, 0);
        int[] locations = {0};
        DocumentSearch.Source source = new DocumentSearch.Source() {
            public int units() { return 1; }
            public String text(int unit) { return "hello ".repeat(450); }
            public DocumentLocator locator(int unit, int offset) {
                locations[0]++;
                search.cancel();
                return DocumentLocator.pdf(0, 1, 0);
            }
        };
        assertThrows(InterruptedException.class, () -> search.next(source));
        assertEquals(1, locations[0]); assertEquals(0, search.offset);
        assertFalse(search.complete);
    }
}
