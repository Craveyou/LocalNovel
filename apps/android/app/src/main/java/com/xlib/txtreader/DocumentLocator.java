package com.xlib.txtreader;

import org.json.JSONObject;
import java.util.Locale;
import java.util.Objects;

/** Versioned, source-document coordinates. Never a byte offset into a PDF/ZIP. */
final class DocumentLocator {
    final String format;
    final int version, page, pageCount, spineIndex, spineCount, textOffset, textLength;
    final double y;
    final String resource,profile,manifestHash,pageKey,textHash;
    boolean isComic(){return "cbz".equals(format)||"cbr".equals(format);}

    private DocumentLocator(String format, int page, int pageCount, double y, String resource,
                            int spineIndex, int spineCount, int textOffset, int textLength) {
        this(format,page,pageCount,y,resource,spineIndex,spineCount,textOffset,textLength,"","","");
    }
    private DocumentLocator(String format,int page,int pageCount,double y,String resource,int spineIndex,int spineCount,int textOffset,int textLength,String profile,String manifestHash,String pageKey) {
        this.profile=profile;this.manifestHash=manifestHash;this.pageKey=pageKey;this.textHash="kindle".equals(format)?manifestHash:"";
        this.format = format; this.version = 1; this.page = page; this.pageCount = pageCount;
        this.y = profile.isEmpty()?Math.floor(y * 1_000_000d + 0.5d) / 1_000_000d:java.math.BigDecimal.valueOf(y).setScale(6,java.math.RoundingMode.HALF_UP).doubleValue();
        this.resource = resource; this.spineIndex = spineIndex; this.spineCount = spineCount;
        this.textOffset = textOffset; this.textLength = textLength;
    }

    static DocumentLocator kindle(String hash,int offset,int length) {
        if(hash==null||!hash.matches("[0-9a-f]{64}")||length<1||offset<0||offset>length)throw new IllegalArgumentException("Kindle 位置无效");
        return new DocumentLocator("kindle",0,0,0,"",0,0,offset,length,KindleDocument.PROFILE,hash,"");
    }
    static DocumentLocator comic(String format,String manifest,String key,int page,int count,double y) {
        if(!("cbz".equals(format)||"cbr".equals(format))||manifest==null||!manifest.matches("[0-9a-f]{64}")||key==null||!key.matches("[0-9a-f]{64}")||count<1||count>10000||page<0||page>=count||!Double.isFinite(y)||y<0||y>1)throw new IllegalArgumentException("漫画位置无效");
        return new DocumentLocator(format,page,count,y,"",0,0,0,0,ComicManifest.PROFILE,manifest,key);
    }
    static DocumentLocator pdf(int page, int count, double y) {
        if (count < 1 || count > 100_000 || page < 0 || page >= count || !Double.isFinite(y) || y < 0 || y > 1)
            throw new IllegalArgumentException("无效的 PDF 位置");
        return new DocumentLocator("pdf", page, count, y, "", 0, 0, 0, 0);
    }

    static DocumentLocator epub(String resource, int index, int count, int offset, int length) {
        if (!safeResource(resource) || count < 1 || count > 10_000 || index < 0 || index >= count
                || length < 0 || offset < 0 || offset > length)
            throw new IllegalArgumentException("无效的 EPUB 位置");
        return new DocumentLocator("epub", 0, 0, 0, resource, index, count, offset, length);
    }

    static boolean safeResource(String path) {
        if (path == null || path.isEmpty() || path.length() > 1024 || path.startsWith("/")
                || path.contains("\\") || path.contains(":") || path.contains("%")
                || path.contains("#") || path.contains("?")) return false;
        for (String part : path.split("/", -1)) if (part.isEmpty() || part.equals(".") || part.equals("..")) return false;
        for (int i = 0; i < path.length(); i++) {
            char c=path.charAt(i);
            if(c<32||c==127)return false;
            if(Character.isHighSurrogate(c)){if(i+1>=path.length()||!Character.isLowSurrogate(path.charAt(++i)))return false;}
            else if(Character.isLowSurrogate(c))return false;
        }
        return true;
    }

    double progress() {
        if("kindle".equals(format))return textOffset/(double)textLength;
        if(isComic())return (page+1d)/pageCount;
        return "pdf".equals(format) ? (page + y) / pageCount
                : (spineIndex + (textLength == 0 ? 0 : textOffset / (double) textLength)) / spineCount;
    }

    String key() {
        if("kindle".equals(format))return "kindle:1:"+profile+":"+textHash+":"+textOffset;
        if(isComic())return format+":1:"+profile+":"+manifestHash+":"+pageKey+":"+String.format(Locale.ROOT,"%.6f",y);
        return "pdf".equals(format) ? "pdf:1:" + page + ":" + String.format(Locale.ROOT, "%.6f", y)
                : "epub:1:" + resource + ":" + textOffset;
    }

    JSONObject json() throws Exception {
        JSONObject value = new JSONObject().put("format", format).put("version", version);
        if("kindle".equals(format))return value.put("profile",profile).put("textHash",textHash).put("textOffset",textOffset).put("textLength",textLength);
        if(isComic())return value.put("profile",profile).put("manifestHash",manifestHash).put("pageKey",pageKey).put("page",page).put("pageCount",pageCount).put("y",y);
        if ("pdf".equals(format)) value.put("page", page).put("pageCount", pageCount).put("y", y);
        else value.put("resource", resource).put("spineIndex", spineIndex).put("spineCount", spineCount)
                .put("textOffset", textOffset).put("textLength", textLength);
        return value;
    }

    static DocumentLocator fromJson(JSONObject value) throws Exception {
        if (integer(value, "version") != 1) throw new IllegalArgumentException("暂不支持此定位版本");
        String format = value.getString("format");
        java.util.Set<String> keys = new java.util.HashSet<>(java.util.Arrays.asList("pdf".equals(format)
            ? new String[]{"format","version","page","pageCount","y"}
            : "kindle".equals(format)?new String[]{"format","version","profile","textHash","textOffset","textLength"} : ("cbz".equals(format)||"cbr".equals(format))?new String[]{"format","version","profile","manifestHash","pageKey","page","pageCount","y"}:new String[]{"format","version","resource","spineIndex","spineCount","textOffset","textLength"}));
        java.util.Iterator<String> names=value.keys();
        while(names.hasNext()) if(!keys.remove(names.next())) throw new IllegalArgumentException("未知定位字段");
        if(!keys.isEmpty()) throw new IllegalArgumentException("定位字段缺失");
        if("kindle".equals(format)){
            if(!KindleDocument.PROFILE.equals(value.getString("profile"))||!(value.get("textHash") instanceof String))throw new IllegalArgumentException("Kindle 定位版本不支持");
            return kindle(value.getString("textHash"),integer(value,"textOffset"),integer(value,"textLength"));
        }
        if("cbz".equals(format)||"cbr".equals(format)){
            if(!ComicManifest.PROFILE.equals(value.getString("profile"))||!(value.get("y") instanceof Number))throw new IllegalArgumentException("漫画定位版本不支持");
            return comic(format,value.getString("manifestHash"),value.getString("pageKey"),integer(value,"page"),integer(value,"pageCount"),value.getDouble("y"));
        }
        if("pdf".equals(format) && !(value.get("y") instanceof Number)) throw new IllegalArgumentException("页内位置无效");
        if ("pdf".equals(format)) return pdf(integer(value, "page"), integer(value, "pageCount"), value.getDouble("y"));
        if ("epub".equals(format)) return epub(value.getString("resource"), integer(value, "spineIndex"),
                integer(value, "spineCount"), integer(value, "textOffset"), integer(value, "textLength"));
        throw new IllegalArgumentException("暂不支持此文档格式");
    }

    private static int integer(JSONObject value, String key) throws Exception {
        Object raw = value.get(key);
        if (!(raw instanceof Number)) throw new IllegalArgumentException("定位整数无效");
        double n = ((Number) raw).doubleValue();
        if (!Double.isFinite(n) || n != Math.rint(n) || n < 0 || n > Integer.MAX_VALUE)
            throw new IllegalArgumentException("定位整数越界");
        return (int)n;
    }

    @Override public boolean equals(Object other) {
        if (!(other instanceof DocumentLocator)) return false;
        DocumentLocator value = (DocumentLocator) other;
        return key().equals(value.key()) && pageCount == value.pageCount && spineCount == value.spineCount
                && spineIndex == value.spineIndex && textLength == value.textLength;
    }
    @Override public int hashCode() { return Objects.hash(key(), pageCount, spineIndex, spineCount, textLength); }
}
