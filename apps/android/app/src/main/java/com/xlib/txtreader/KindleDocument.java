package com.xlib.txtreader;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/** Shared core output, without an Android-specific canonical-text transformation. */
final class KindleDocument extends ReflowDocument {
    static final String PROFILE="kindle-text-v1";
    final String canonicalText,textHash,mode,coverResource;
    final JSONObject output;
    private final File source;
    private final long size,modified;
    private final JSONObject resources;
    private final int[] starts;
    KindleDocument(Context context,File source,ComicArchive.Cancellation cancel)throws Exception {
        this(source,parse(context,source,cancel));
        for(Iterator<String> names=resources.keys();names.hasNext();) {
            ComicArchive.check(cancel);byte[] bytes=read(names.next());BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;
            BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
            if(options.outWidth<1||options.outHeight<1||(long)options.outWidth*options.outHeight>100_000_000L)throw new IOException("Kindle 图片无效或过大");
            options.inJustDecodeBounds=false;options.inSampleSize=1;
            while(options.outWidth/options.inSampleSize>1||options.outHeight/options.inSampleSize>1)options.inSampleSize*=2;
            Bitmap thumbnail=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
            if(thumbnail==null)throw new IOException("Kindle 图片无法解码");thumbnail.recycle();
        }
        ComicArchive.check(cancel);checkSource();
    }
    private static JSONObject parse(Context context,File file,ComicArchive.Cancellation cancel)throws Exception {
        long length=file.length(),modified=file.lastModified();KindleContainer.inspect(file,cancel);
        JSONObject output=new JSONObject(KindleEngine.parse(context,file,cancel));
        if(length!=file.length()||modified!=file.lastModified())throw new IOException("Kindle 解析期间原文件已改变");return output;
    }
    // Also used by host-independent contract tests; output must come from the shared core.
    KindleDocument(File source,JSONObject output)throws Exception {
        this.source=source;this.size=source.length();this.modified=source.lastModified();this.output=output;
        if(output.getInt("coreVersion")!=1||!PROFILE.equals(output.getString("profile")))throw new IOException("Kindle 核心版本不支持");
        canonicalText=output.getString("canonicalText");mode=output.getString("mode");resources=output.getJSONObject("resources");
        coverResource=output.isNull("coverResource")?null:output.getString("coverResource");
        JSONArray units=output.getJSONArray("chapters");starts=new int[units.length()];StringBuilder joined=new StringBuilder();
        for(int i=0;i<units.length();i++) {
            JSONObject unit=units.getJSONObject(i);starts[i]=unit.getInt("textStart");
            if(i>0)joined.append('\n');if(starts[i]!=joined.length())throw new IOException("Kindle 章节坐标不一致");
            String text=unit.getString("text");joined.append(text);Map<String,Integer> anchors=new HashMap<>();JSONObject positions=unit.getJSONObject("anchors");
            for(Iterator<String> names=positions.keys();names.hasNext();){String key=names.next();anchors.put(key,positions.getInt(key));}
            chapters.add(new Chapter(unit.getString("resource"),unit.getString("html"),text,anchors));
        }
        if(canonicalText.isEmpty()||!canonicalText.contentEquals(joined))throw new IOException("Kindle 正文不一致");
        byte[] digest=MessageDigest.getInstance("SHA-256").digest(canonicalText.getBytes(StandardCharsets.UTF_8));StringBuilder hash=new StringBuilder();
        for(byte value:digest)hash.append(String.format(Locale.ROOT,"%02x",value&255));textHash=hash.toString();
        JSONArray navigation=output.getJSONArray("toc");for(int i=0;i<navigation.length();i++){JSONObject entry=navigation.getJSONObject(i);int unit=entry.getInt("unit"),offset=entry.getInt("offset");if(unit<0||unit>=chapters.size()||offset<0||offset>chapters.get(unit).text.length())throw new IOException("Kindle 目录坐标无效");toc.add(new Toc(entry.getString("title"),unit,offset));}
    }
    private void checkSource()throws IOException {if(source.length()!=size||source.lastModified()!=modified)throw new IOException("Kindle 原文件已改变，原位置保留");}
    @Override byte[] read(String path)throws IOException {
        checkSource();if(!DocumentLocator.safeResource(path))throw new IOException("资源路径无效");
        try{JSONObject item=resources.getJSONObject(path);long offset=item.getLong("offset");int count=item.getInt("size");if(count<0||count>16*1024*1024||offset<0||offset>size-count)throw new IOException("资源越界");
            byte[] bytes=new byte[count];try(RandomAccessFile input=new RandomAccessFile(source,"r")){input.seek(offset);input.readFully(bytes);}return bytes;
        }catch(JSONException error){throw new IOException("Kindle 本地资源不存在",error);}
    }
    @Override DocumentLocator locator(int chapter,int offset){return DocumentLocator.kindle(textHash,starts[chapter]+ReaderTextSelection.boundary(chapters.get(chapter).text,offset),canonicalText.length());}
    DocumentLocator atOffset(int offset){DocumentLocator raw=DocumentLocator.kindle(textHash,Math.max(0,Math.min(canonicalText.length(),offset)),canonicalText.length());return locator(chapterIndex(raw),localOffset(raw));}
    @Override int chapterIndex(DocumentLocator value){int index=0;for(int i=1;i<starts.length&&starts[i]<=value.textOffset;i++)index=i;return index;}
    @Override int localOffset(DocumentLocator value){int i=chapterIndex(value);return Math.min(chapters.get(i).text.length(),value.textOffset-starts[i]);}
    @Override boolean valid(DocumentLocator value){return value!=null&&"kindle".equals(value.format)&&textHash.equals(value.textHash)&&canonicalText.length()==value.textLength&&value.textOffset>=0&&value.textOffset<=canonicalText.length()&&locator(chapterIndex(value),localOffset(value)).equals(value);}
    @Override String searchText(int unit){return chapters.get(unit).text.replace('\ufffc',' ');}
    int[] sourceRange(int chapter,int offset)throws JSONException{return mapped(chapter,offset,false);}
    int[] canonicalRange(int chapter,int offset)throws JSONException{return mapped(chapter,offset,true);}
    private int[] mapped(int chapter,int offset,boolean reverse)throws JSONException {
        JSONArray maps=output.getJSONArray("chapters").getJSONObject(chapter).getJSONArray("maps");
        for(int i=0;i<maps.length();i++){JSONObject span=maps.getJSONObject(i);int ts=span.getInt("textStart"),te=span.getInt("textEnd"),ss=span.getInt("sourceStart"),se=span.getInt("sourceEnd");if(ss<0)continue;
            int begin=reverse?ss:ts,end=reverse?se:te;if(offset<begin||offset>=end)continue;
            int target=reverse?ts:ss,targetEnd=reverse?te:se;
            if("text".equals(span.getString("kind"))&&te-ts==se-ss)return new int[]{target+offset-begin,1};return new int[]{target,targetEnd-target};}
        return null;
    }
    @Override public void close(){}
}
