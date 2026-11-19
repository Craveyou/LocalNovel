package com.xlib.txtreader;

import static org.junit.Assert.*;
import org.junit.Test;
import org.json.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class ComicContractTest {
    private JSONObject fixture(String path)throws Exception {try(java.io.InputStream input=getClass().getClassLoader().getResourceAsStream(path)){assertNotNull(path,input);return new JSONObject(new String(input.readAllBytes(),StandardCharsets.UTF_8));}}
    private JSONObject merged(JSONObject base,JSONObject extra)throws Exception {JSONObject result=new JSONObject(base.toString());for(Iterator<String> i=extra.keys();i.hasNext();){String key=i.next();result.put(key,extra.get(key));}return result;}
    @Test public void locatorVectorsAndDecimalHalfUpMatchFrozenContract()throws Exception {
        JSONObject vectors=fixture("comic-locators.json"),base=vectors.getJSONObject("base");
        JSONArray valid=vectors.getJSONArray("validOverrides");for(int i=0;i<valid.length();i++){JSONObject v=valid.getJSONObject(i);DocumentLocator p=DocumentLocator.fromJson(merged(base,v.getJSONObject("overrides")));assertEquals(v.getDouble("progress"),p.progress(),0);assertEquals(p,DocumentLocator.fromJson(p.json()));assertFalse(p.json().has("path"));}
        JSONArray rounding=vectors.getJSONArray("rounding");for(int i=0;i<rounding.length();i++){JSONObject v=rounding.getJSONObject(i);DocumentLocator p=DocumentLocator.fromJson(merged(base,new JSONObject().put("y",v.getDouble("input"))));assertEquals(v.toString(),v.getDouble("expected"),p.y,0);assertTrue(p.key().endsWith(String.format(Locale.ROOT,"%.6f",p.y)));}
        JSONArray invalid=vectors.getJSONArray("invalidOverrides");for(int i=0;i<invalid.length();i++){JSONObject v=invalid.getJSONObject(i);JSONObject input=merged(base,v.getJSONObject("overrides"));assertThrows(v.getString("id"),Exception.class,()->DocumentLocator.fromJson(input));}
    }
    @Test public void everyFrozenPageOrderAndIdentityMatchesIncludingUnicodeAndNumericTies()throws Exception {
        JSONObject vectors=fixture("documents/comic-order-v1.json");List<ComicArchive.Entry> entries=new ArrayList<>();JSONArray raw=vectors.getJSONArray("entries");
        for(int i=0;i<raw.length();i++){JSONObject v=raw.getJSONObject(i);String name=ComicArchive.canonical(v.getString("path"));entries.add(new ComicArchive.Entry(name,0,0,0,0,0,0,new byte[0]));}
        List<ComicArchive.Entry> pages=ComicArchive.pages(entries);ComicManifest manifest=new ComicManifest(pages);JSONArray expected=vectors.getJSONArray("pages");assertEquals(expected.length(),pages.size());assertEquals(vectors.getString("manifestHash"),manifest.hash);
        for(int i=0;i<pages.size();i++){assertEquals(expected.getJSONObject(i).getString("canonicalPath"),pages.get(i).name);assertEquals(expected.getJSONObject(i).getString("pageKey"),manifest.keys.get(i));DocumentLocator p=manifest.locator("cbz",i,.5);assertTrue(manifest.valid(p,"cbz"));assertFalse(manifest.valid(p,"cbr"));assertFalse(manifest.valid(DocumentLocator.comic("cbz",manifest.hash,"00".repeat(32),i,pages.size(),0),"cbz"));}
    }
    @Test public void originalCbzManifestMatchesSharedArchiveFixture()throws Exception {
        java.io.File source=java.io.File.createTempFile("comic-contract-",".cbz");try(java.io.InputStream input=getClass().getClassLoader().getResourceAsStream("documents/comic-basic.cbz")){java.nio.file.Files.copy(input,source.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING);}
        try(ComicArchive archive=new ComicArchive(source,ComicArchive.NEVER)){JSONObject fixture=fixture("documents/comic-basic.json");ComicManifest manifest=new ComicManifest(archive.pages());assertEquals(fixture.getString("manifestHash"),manifest.hash);assertEquals(fixture.getInt("pageCount"),manifest.keys.size());}finally{source.delete();}
    }
}
