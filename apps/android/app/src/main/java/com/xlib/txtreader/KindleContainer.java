package com.xlib.txtreader;

import java.io.EOFException;
import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Bounded container inspection only; canonical text and reading positions belong to the shared engine. */
final class KindleContainer {
    enum Mode { MOBI, KF8, MIXED }
    final Mode mode;
    final int headerRecord, recordCount, version, compression, encoding;
    private static final long UNSET = 0xffffffffL;
    private static final int MAX_HEADER = 1024 * 1024, MAX_EXTH_RECORDS = 1024;

    private KindleContainer(Mode mode, int selected, int records, Header header) {
        this.mode = mode; headerRecord = selected; recordCount = records;
        version = header.version; compression = header.compression; encoding = header.encoding;
    }
    static KindleContainer inspect(File source, ComicArchive.Cancellation cancel) throws IOException {
        ComicArchive.check(cancel);
        long size = source.length(), modified = source.lastModified();
        if (size > ComicArchive.MAX_SOURCE) throw unsupported("Kindle 文件超过 1 GiB");
        try (RandomAccessFile file = new RandomAccessFile(source, "r")) {
            if (size < 78) throw broken("数据库头不完整");
            file.seek(60);
            if (!magic(file, "BOOKMOBI")) throw broken("数据库类型不符");
            file.seek(72);
            if (u32(file) != 0) throw unsupported("暂不支持多记录表 Kindle 文件");
            int count = file.readUnsignedShort();
            long tableEnd = 78L + count * 8L;
            if (count < 2 || tableEnd > size) throw broken("记录表越界");
            long[] offsets = new long[count + 1];
            for (int i = 0; i < count; i++) {
                if ((i & 127) == 0) ComicArchive.check(cancel);
                offsets[i] = u32(file); file.skipBytes(4);
                if (offsets[i] < tableEnd || offsets[i] > size || (i > 0 && offsets[i] < offsets[i - 1]))
                    throw broken("记录位置无效");
            }
            offsets[count] = size;
            Header first = header(file, offsets, 0, cancel);
            int selected = 0; Header chosen = first;
            Mode mode = first.version == 8 ? Mode.KF8 : Mode.MOBI;
            if (first.boundary != UNSET) {
                // EXTH 121 names the KF8 header record. Its predecessor must be
                // the BOUNDARY record; never scan for a convenient fallback.
                if (first.version == 8 || first.boundary < 2 || first.boundary >= count - 1)
                    throw broken("混合格式边界无效");
                selected = (int) first.boundary;
                if (offsets[selected] - offsets[selected - 1] < 8) throw broken("混合格式分隔记录不完整");
                file.seek(offsets[selected - 1]);
                if (!magic(file, "BOUNDARY")) throw broken("混合格式分隔记录缺失");
                if (first.textRecords >= selected - 1) throw broken("旧版正文越过混合格式边界");
                chosen = header(file, offsets, selected, cancel);
                if (chosen.version != 8 || chosen.boundary != UNSET) throw broken("混合格式 KF8 头无效");
                mode = Mode.MIXED;
            }
            ComicArchive.check(cancel);
            if (source.length() != size || source.lastModified() != modified) throw broken("检查期间原文件已改变");
            return new KindleContainer(mode, selected, count, chosen);
        } catch (EOFException error) { throw broken("文件被截断"); }
    }
    String description() {
        return mode == Mode.MIXED ? "MOBI/KF8 混合格式（选用 KF8）" : mode == Mode.KF8 ? "KF8" : "MOBI";
    }
    private static Header header(RandomAccessFile file, long[] offsets, int index,
                                 ComicArchive.Cancellation cancel) throws IOException {
        ComicArchive.check(cancel);
        long start = offsets[index], end = offsets[index + 1], length = end - start;
        if (length < 40 || length > MAX_HEADER) throw broken("正文头大小无效");
        file.seek(start); int compression = file.readUnsignedShort();
        file.seek(start + 4); long textBytes = u32(file); int textRecords = file.readUnsignedShort();
        file.seek(start + 12);
        if (file.readUnsignedShort() != 0) throw unsupported("不支持带 DRM 的 Kindle 电子书");
        if (compression != 1 && compression != 2 && compression != 17480) throw unsupported("不支持此 Kindle 压缩方式");
        if (textBytes == 0 || textRecords == 0 || (long) index + textRecords >= offsets.length - 1)
            throw broken("正文记录数量无效");
        for (int i = index + 1; i <= index + textRecords; i++) {
            if ((i & 127) == 0) ComicArchive.check(cancel);
            if (offsets[i + 1] <= offsets[i]) throw broken("正文记录为空");
        }
        file.seek(start + 16);
        if (!magic(file, "MOBI")) throw broken("MOBI 标记缺失");
        long headerLength = u32(file);
        if (headerLength < 116 || headerLength > length - 16) throw broken("MOBI 头长度无效");
        file.seek(start + 28); long encoding = u32(file);
        file.seek(start + 36); long version = u32(file);
        if (version != 6 && version != 7 && version != 8) throw unsupported("不支持此 MOBI 版本");
        if (encoding != 1252 && encoding != 65001) throw unsupported("不支持此 Kindle 正文编码");
        if (headerLength >= 168) {
            file.seek(start + 172); long cookies = u32(file), drmBytes = u32(file), drmFlags = u32(file);
            if (cookies != 0 || drmBytes != 0 || (drmFlags & 1) != 0)
                throw unsupported("不支持带 DRM 的 Kindle 电子书");
        }
        file.seek(start + 128); long flags = u32(file), boundary = UNSET;
        if ((flags & 0x40) != 0) {
            long exth = start + 16 + headerLength;
            if (exth > end - 12) throw broken("EXTH 头越界");
            file.seek(exth);
            if (!magic(file, "EXTH")) throw broken("EXTH 标记缺失");
            long exthLength = u32(file), entries = u32(file);
            if (exthLength < 12 || exthLength > end - exth || entries > MAX_EXTH_RECORDS || entries > (exthLength - 12) / 8)
                throw broken("EXTH 记录表无效");
            long cursor = exth + 12, limit = exth + exthLength; boolean seenBoundary = false;
            for (int i = 0; i < entries; i++) {
                ComicArchive.check(cancel);
                if (cursor > limit - 8) throw broken("EXTH 记录越界");
                file.seek(cursor); long tag = u32(file), bytes = u32(file);
                if (bytes < 8 || bytes > limit - cursor) throw broken("EXTH 记录长度无效");
                if (tag == 121) {
                    if (seenBoundary || bytes != 12) throw broken("混合格式边界重复或无效");
                    seenBoundary = true; boundary = u32(file);
                } else if (tag == 122) {
                    if (bytes > 24) throw unsupported("暂不支持固定版式 Kindle 电子书");
                    byte[] value = new byte[(int) bytes - 8]; file.readFully(value);
                    String fixed = new String(value, StandardCharsets.US_ASCII).trim();
                    if (!fixed.isEmpty() && !fixed.equalsIgnoreCase("false") && !fixed.equalsIgnoreCase("no") && !fixed.equals("0"))
                        throw unsupported("暂不支持固定版式 Kindle 电子书");
                }
                cursor += bytes;
            }
        }
        if (compression == 1 && offsets[index + 2] - offsets[index + 1] >= 4) {
            file.seek(offsets[index + 1]);
            if (magic(file, "%MOP")) throw unsupported("暂不支持 Print Replica 固定版式 Kindle 电子书");
        }
        return new Header((int) version, compression, (int) encoding, textRecords, boundary);
    }
    private static long u32(RandomAccessFile file) throws IOException { return file.readInt() & UNSET; }
    private static boolean magic(RandomAccessFile file, String value) throws IOException {
        byte[] bytes = new byte[value.length()]; file.readFully(bytes);
        return Arrays.equals(bytes, value.getBytes(StandardCharsets.US_ASCII));
    }
    private static DocumentFormats.UnsupportedDocumentException broken(String reason) {
        return unsupported("Kindle 文件损坏：" + reason);
    }
    private static DocumentFormats.UnsupportedDocumentException unsupported(String reason) {
        return new DocumentFormats.UnsupportedDocumentException(reason);
    }
    private static final class Header {
        final int version, compression, encoding, textRecords; final long boundary;
        Header(int version, int compression, int encoding, int textRecords, long boundary) {
            this.version = version; this.compression = compression; this.encoding = encoding;
            this.textRecords = textRecords; this.boundary = boundary;
        }
    }
}
