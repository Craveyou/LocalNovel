package com.xlib.txtreader;

import java.io.IOException;
import java.util.*;

/** Shared display model; each format retains its own source-coordinate contract. */
abstract class ReflowDocument implements AutoCloseable {
    final List<Chapter> chapters = new ArrayList<>();
    final List<Toc> toc = new ArrayList<>();
    static final class Chapter {
        final String resource, html, text;
        final Map<String,Integer> anchors;
        Chapter(String resource,String html,String text,Map<String,Integer> anchors) {
            this.resource=resource;this.html=html;this.text=text;this.anchors=anchors;
        }
    }
    static final class Toc {
        final String title; final int chapter,offset;
        Toc(String title,int chapter,int offset){this.title=title;this.chapter=chapter;this.offset=offset;}
    }
    abstract byte[] read(String path) throws IOException;
    abstract DocumentLocator locator(int chapter,int offset);
    abstract boolean valid(DocumentLocator value);
    int chapterIndex(DocumentLocator value){return value.spineIndex;}
    int localOffset(DocumentLocator value){return value.textOffset;}
    String searchText(int unit){return chapters.get(unit).text;}
    @Override public abstract void close() throws IOException;
}
