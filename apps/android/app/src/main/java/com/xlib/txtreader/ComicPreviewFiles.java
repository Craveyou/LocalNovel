package com.xlib.txtreader;

import java.io.File;
import java.io.IOException;

/** Session copies and scratch files share a hard disk budget; no archive-named output is allowed. */
final class ComicPreviewFiles {
    private ComicPreviewFiles() { }
    static void reserve(File session,long additional)throws IOException {
        if(session.getUsableSpace()<additional+16L*1024*1024)throw new IOException("存储空间不足，无法准备漫画");
        File parent=session.getParentFile();File root=parent!=null&&parent.getName().equals("comic-previews")?parent:session;
        if(size(root)+additional>ComicArchive.MAX_SOURCE)throw new IOException("漫画预览临时文件超过 1 GiB，请退出其他预览或清理缓存后重试");
    }
    private static long size(File file) {
        if(file.isFile())return file.length();long total=0;File[] children=file.listFiles();
        if(children!=null)for(File child:children){total+=size(child);if(total>ComicArchive.MAX_SOURCE)break;}
        return total;
    }
}
