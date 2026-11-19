package com.xlib.txtreader;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Frozen comic-order-v1 page identities; paths stay local and are never sent to the service. */
final class ComicManifest {
    static final String PROFILE="comic-order-v1";
    final String hash;
    final List<String> keys=new ArrayList<>();
    ComicManifest(List<ComicArchive.Entry> sorted){
        StringBuilder value=new StringBuilder("xlib-comic-order-v1\n");
        for(ComicArchive.Entry entry:sorted){String key=sha(entry.name);keys.add(key);value.append(key).append('\n');}
        hash=sha(value.toString());
    }
    DocumentLocator locator(String format,int page,double y){return DocumentLocator.comic(format,hash,keys.get(page),page,keys.size(),y);}
    boolean valid(DocumentLocator value,String format){return value!=null&&format.equals(value.format)&&PROFILE.equals(value.profile)&&hash.equals(value.manifestHash)&&value.pageCount==keys.size()&&value.page>=0&&value.page<keys.size()&&keys.get(value.page).equals(value.pageKey);}
    static String sha(String value){try{byte[] bytes=MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder();for(byte b:bytes)out.append(String.format(Locale.ROOT,"%02x",b&255));return out.toString();}catch(Exception e){throw new IllegalStateException(e);}}
}
