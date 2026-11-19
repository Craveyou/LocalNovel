package com.xlib.txtreader;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk={23,35})
public class SharedDocumentFixtureTest {
    private byte[] fixture(String name)throws Exception{
        try(java.io.InputStream input=getClass().getClassLoader().getResourceAsStream("documents/"+name)){assertNotNull(input);return input.readAllBytes();}
    }
    @Test public void epubAndCoordinateVectorsMatchSwiftAndBackend()throws Exception{
        File file=File.createTempFile("interop-",".epub");Files.write(file.toPath(),fixture("reflow.epub"));
        try(EpubDocument epub=new EpubDocument(RuntimeEnvironment.getApplication(),file)){
            JSONArray text=new JSONArray(new String(fixture("canonical-text.json"),StandardCharsets.UTF_8));
            for(int i=0;i<2;i++)assertEquals(text.getString(i),epub.chapters.get(i).text);
            assertEquals(2,epub.toc.size());assertFalse(epub.chapters.get(0).html.contains("authoredScriptExecuted"));
            JSONArray vectors=new JSONArray(new String(fixture("coordinates.json"),StandardCharsets.UTF_8));
            for(int i=0;i<vectors.length();i++){
                JSONObject vector=vectors.getJSONObject(i);DocumentLocator locator=DocumentLocator.fromJson(vector.getJSONObject("locator"));
                assertEquals(vector.getDouble("progress"),locator.progress(),1e-9);
                if("epub".equals(locator.format))assertTrue(epub.valid(locator));
            }
            assertEquals(epub.locator(0,4),epub.locator(0,5));
        }finally{assertTrue(file.delete());}
    }
}
