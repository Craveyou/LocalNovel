package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.content.Context;
import android.graphics.Color;
import android.graphics.RectF;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import com.tom_roush.pdfbox.pdmodel.PDPage;
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream;
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font;
import java.io.File;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class PdfRenderingDeviceTest {
    @Test public void nativeRenderingKeepsRotatedGlyphGeometryAndMeasuresRasterization()throws Exception{
        assertTrue(android.os.Build.HARDWARE.contains("ranchu")||android.os.Build.HARDWARE.contains("goldfish"));
        Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();PDFBoxResourceLoader.init(context);
        File file=new File(context.getCacheDir(),"native-render-fixture.pdf");
        try(PDDocument document=new PDDocument()){
            for(int rotation:new int[]{0,90,180,270}){
                PDPage page=new PDPage();page.setRotation(rotation);
                page.setCropBox(new com.tom_roush.pdfbox.pdmodel.common.PDRectangle(40,30,500,700));document.addPage(page);
                try(PDPageContentStream out=new PDPageContentStream(document,page)){
                    for(int i=0;i<1800;i++){out.setNonStrokingColor((i*13)%256,(i*31)%256,(i*7)%256);out.addRect(25+(i%60)*9,200+(i/60)*9,5,5);out.fill();}
                    out.setNonStrokingColor(0,0,0);out.beginText();out.setFont(PDType1Font.HELVETICA,20);out.newLineAtOffset(200,700);out.showText("Hello native PDF");out.endText();
                }
            }document.save(file);
        }
        try(PdfDocument pdf=new PdfDocument(context,file,null)){
            Field engine=PdfDocument.class.getDeclaredField("nativeRenderer");engine.setAccessible(true);Object nativeEngine=engine.get(pdf);assertNotNull("Real Android native engine must be active",nativeEngine);
            for(int page=0;page<4;page++){
                PdfDocument.Page rendered=pdf.render(page,1080);RectF box=rendered.boxes.get(0);float sx=rendered.bitmap.getWidth()/rendered.width,sy=rendered.bitmap.getHeight()/rendered.height;boolean ink=false;
                for(int y=Math.max(0,(int)(box.top*sy)-3);y<Math.min(rendered.bitmap.getHeight(),(int)(box.bottom*sy)+3);y++)
                    for(int x=Math.max(0,(int)(box.left*sx)-3);x<Math.min(rendered.bitmap.getWidth(),(int)(box.right*sx)+3);x++)if(Color.red(rendered.bitmap.getPixel(x,y))<100)ink=true;
                assertTrue("Native text geometry at rotation "+page*90,ink);rendered.bitmap.recycle();assertSame(nativeEngine,engine.get(pdf));
            }
            double[] nativeMs=new double[3],fallbackMs=new double[3];
            // Both paths use the same loaded document/text extraction, resolution and warmed fixture.
            for(int run=0;run<3;run++){
                long begin=System.nanoTime();PdfDocument.Page page=pdf.render(0,1080);nativeMs[run]=(System.nanoTime()-begin)/1e6;page.bitmap.recycle();
                engine.set(pdf,null);
                try{begin=System.nanoTime();page=pdf.render(0,1080);fallbackMs[run]=(System.nanoTime()-begin)/1e6;page.bitmap.recycle();}finally{engine.set(pdf,nativeEngine);}
            }
            String json="{\"fixture\":\"1800-vector-rectangles\",\"width\":1080,\"nativeMs\":"+java.util.Arrays.toString(nativeMs)+",\"pdfBoxMs\":"+java.util.Arrays.toString(fallbackMs)+"}\n";
            Files.write(new File(context.getExternalFilesDir(null),"pdf-rendering-measurements.json").toPath(),json.getBytes(StandardCharsets.UTF_8));
        }
    }
}
