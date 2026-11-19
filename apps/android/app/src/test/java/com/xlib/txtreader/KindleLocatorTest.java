package com.xlib.txtreader;
import static org.junit.Assert.*;
import java.nio.charset.StandardCharsets;
import org.json.*;
import org.junit.Test;

public class KindleLocatorTest {
    private JSONObject merge(JSONObject base,JSONObject patch)throws Exception {
        JSONObject value=new JSONObject(base.toString());for(java.util.Iterator<String> it=patch.keys();it.hasNext();){String key=it.next();value.put(key,patch.get(key));}return value;
    }
    @Test public void consumesEverySharedKindleLocatorVector()throws Exception {
        JSONObject fixture;try(java.io.InputStream input=getClass().getResourceAsStream("/kindle-locators.json")){fixture=new JSONObject(new String(input.readAllBytes(),StandardCharsets.UTF_8));}
        JSONObject base=fixture.getJSONObject("base");JSONArray valid=fixture.getJSONArray("validOverrides"),invalid=fixture.getJSONArray("invalidOverrides");
        for(int i=0;i<valid.length();i++){JSONObject item=valid.getJSONObject(i),value=merge(base,item.getJSONObject("overrides"));DocumentLocator locator=DocumentLocator.fromJson(value);assertEquals(item.getDouble("progress"),locator.progress(),.00000001);assertEquals(value.toString(),locator.json().toString());assertEquals(locator,DocumentLocator.fromJson(locator.json()));assertTrue(locator.key().startsWith("kindle:1:kindle-text-v1:"));}
        for(int i=0;i<invalid.length();i++){JSONObject item=invalid.getJSONObject(i),value=merge(base,item.getJSONObject("overrides"));assertThrows(item.getString("id"),Exception.class,()->DocumentLocator.fromJson(value));}
    }
}
