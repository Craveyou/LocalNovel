package com.xlib.txtreader;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Original synthetic container structures, not shared canonical-text fixtures. */
final class KindleTestFiles {
    static final byte[] TEXT = "<html><body>中文 👩‍💻 sample</body></html>".getBytes(StandardCharsets.UTF_8);
    static byte[] single(int version) { return pdb(header(version), TEXT); }
    static byte[] mixed() {
        return pdb(header(6, exth(121, integer(3))), TEXT,
                "BOUNDARY".getBytes(StandardCharsets.US_ASCII), header(8), TEXT);
    }
    static byte[] header(int version, byte[]... records) {
        int headerLength = version == 8 ? 264 : 232;
        int exthLength = 12 + Arrays.stream(records).mapToInt(r -> r.length).sum();
        ByteBuffer out = ByteBuffer.allocate(16 + headerLength + (records.length == 0 ? 0 : exthLength)).order(ByteOrder.BIG_ENDIAN);
        out.putShort(0, (short) 1); out.putInt(4, TEXT.length); out.putShort(8, (short) 1); out.putShort(10, (short) 4096);
        out.position(16); out.put("MOBI".getBytes(StandardCharsets.US_ASCII)); out.putInt(headerLength);
        out.putInt(24, 2); out.putInt(28, 65001); out.putInt(32, 42); out.putInt(36, version); out.putInt(168, -1);
        if (records.length != 0) {
            out.putInt(128, 0x40); out.position(16 + headerLength);
            out.put("EXTH".getBytes(StandardCharsets.US_ASCII)); out.putInt(exthLength); out.putInt(records.length);
            for (byte[] record : records) out.put(record);
        }
        return out.array();
    }
    static byte[] integer(int value) { return ByteBuffer.allocate(4).putInt(value).array(); }
    static byte[] exth(int tag, byte[] value) {
        return ByteBuffer.allocate(8 + value.length).putInt(tag).putInt(8 + value.length).put(value).array();
    }
    static byte[] pdb(byte[]... records) {
        int tableEnd = 78 + 8 * records.length + 2;
        ByteBuffer out = ByteBuffer.allocate(tableEnd + Arrays.stream(records).mapToInt(r -> r.length).sum());
        out.position(60); out.put("BOOKMOBI".getBytes(StandardCharsets.US_ASCII)); out.putShort(76, (short) records.length);
        int offset = tableEnd;
        for (int i = 0; i < records.length; i++) { out.putInt(78 + 8 * i, offset); offset += records[i].length; }
        out.position(tableEnd); for (byte[] record : records) out.put(record);
        return out.array();
    }
    static int recordOffset(byte[] file, int index) { return ByteBuffer.wrap(file).getInt(78 + 8 * index); }
    static void intAt(byte[] file, int offset, int value) { ByteBuffer.wrap(file).putInt(offset, value); }
}
