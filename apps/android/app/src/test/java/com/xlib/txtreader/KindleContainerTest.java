package com.xlib.txtreader;

import static org.junit.Assert.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class KindleContainerTest {
    @Rule public TemporaryFolder folder = new TemporaryFolder();
    private File file(byte[] bytes) throws Exception {
        File file = folder.newFile(); Files.write(file.toPath(), bytes); return file;
    }
    private IOException reject(byte[] bytes) throws Exception {
        File file = file(bytes); byte[] before = Files.readAllBytes(file.toPath());
        IOException error = assertThrows(IOException.class, () -> KindleContainer.inspect(file, ComicArchive.NEVER));
        assertArrayEquals(before, Files.readAllBytes(file.toPath())); return error;
    }
    @Test public void recognizesMobiKf8AndMixedByContentAcrossAliases() throws Exception {
        for (int version : new int[]{6, 7, 8}) {
            File file = file(KindleTestFiles.single(version)); KindleContainer result = KindleContainer.inspect(file, ComicArchive.NEVER);
            assertEquals(version == 8 ? KindleContainer.Mode.KF8 : KindleContainer.Mode.MOBI, result.mode);
            assertEquals(version, result.version); assertEquals(0, result.headerRecord); assertEquals(65001, result.encoding);
            for (String name : List.of("book.MOBI", "book.AZW", "book.azw3", "unknown.bin")) assertEquals("kindle", DocumentFormats.detect(file, name));
            assertThrows(IOException.class, () -> DocumentFormats.detect(file, "fake.epub"));
            assertThrows(IOException.class, () -> DocumentFormats.detect(file, "fake.txt"));
        }
        KindleContainer mixed = KindleContainer.inspect(file(KindleTestFiles.mixed()), ComicArchive.NEVER);
        assertEquals(KindleContainer.Mode.MIXED, mixed.mode); assertEquals(3, mixed.headerRecord); assertEquals(8, mixed.version);
    }
    @Test public void brokenMixedKf8NeverFallsBackToValidMobi() throws Exception {
        for (int field : new int[]{16, 20, 36}) {
            byte[] bytes = KindleTestFiles.mixed(); int chosen = KindleTestFiles.recordOffset(bytes, 3);
            KindleTestFiles.intAt(bytes, chosen + field, field == 36 ? 6 : 0);
            reject(bytes);
        }
        byte[] bytes = KindleTestFiles.mixed(); bytes[KindleTestFiles.recordOffset(bytes, 2)] = 'x'; reject(bytes);
        for (int index : new int[]{0, 1, 4, Integer.MAX_VALUE}) {
            reject(KindleTestFiles.pdb(KindleTestFiles.header(6, KindleTestFiles.exth(121, KindleTestFiles.integer(index))), KindleTestFiles.TEXT));
        }
    }
    @Test public void drmInEitherHeaderAndDrmMetadataAreRejected() throws Exception {
        for (int header : new int[]{0, 3}) {
            for (int encryption : new int[]{1, 2, 255}) {
                byte[] bytes = KindleTestFiles.mixed(); bytes[KindleTestFiles.recordOffset(bytes, header) + 13] = (byte) encryption;
                assertTrue(reject(bytes).getMessage().contains("DRM"));
            }
            for (int field : new int[]{172, 176, 180}) {
                byte[] bytes = KindleTestFiles.mixed(); KindleTestFiles.intAt(bytes, KindleTestFiles.recordOffset(bytes, header) + field, 1);
                assertTrue(reject(bytes).getMessage().contains("DRM"));
            }
        }
    }
    @Test public void entireRecordTableIsCheckedUsingUnsignedBounds() throws Exception {
        for (int badOffset : new int[]{0, 78, -1, Integer.MAX_VALUE}) {
            byte[] bytes = KindleTestFiles.mixed(); KindleTestFiles.intAt(bytes, 78 + 4 * 8, badOffset); reject(bytes);
        }
        byte[] bytes = KindleTestFiles.mixed(); KindleTestFiles.intAt(bytes, 72, 80); reject(bytes);
        bytes = KindleTestFiles.mixed(); bytes[76] = (byte) 255; bytes[77] = (byte) 255; reject(bytes);
        bytes = KindleTestFiles.single(6); KindleTestFiles.intAt(bytes, 20 + KindleTestFiles.recordOffset(bytes, 0), -1); reject(bytes);
        bytes = KindleTestFiles.single(8); bytes = Arrays.copyOf(bytes, KindleTestFiles.recordOffset(bytes, 1)); reject(bytes);
    }
    @Test public void malformedExthAndAmbiguousBoundariesAreRejected() throws Exception {
        byte[] boundary = KindleTestFiles.exth(121, KindleTestFiles.integer(3));
        reject(KindleTestFiles.pdb(KindleTestFiles.header(6, boundary, boundary), KindleTestFiles.TEXT));
        reject(KindleTestFiles.pdb(KindleTestFiles.header(6, KindleTestFiles.exth(121, new byte[]{3})), KindleTestFiles.TEXT));
        for (int field : new int[]{4, 8, 16}) {
            byte[] bytes = KindleTestFiles.mixed(); int exth = KindleTestFiles.recordOffset(bytes, 0) + 16 + 232;
            KindleTestFiles.intAt(bytes, exth + field, -1); reject(bytes);
        }
        byte[] nested = KindleTestFiles.pdb(KindleTestFiles.header(6, boundary), KindleTestFiles.TEXT,
                "BOUNDARY".getBytes(StandardCharsets.US_ASCII), KindleTestFiles.header(8, boundary), KindleTestFiles.TEXT);
        reject(nested);
    }
    @Test public void unsupportedVersionsEncodingsCompressionAndFixedLayoutFailExplicitly() throws Exception {
        for (int[] mutation : new int[][]{{36, 9}, {28, 932}, {0, 0x00030000}}) {
            byte[] bytes = KindleTestFiles.single(6); KindleTestFiles.intAt(bytes, KindleTestFiles.recordOffset(bytes, 0) + mutation[0], mutation[1]); reject(bytes);
        }
        byte[] fixed = KindleTestFiles.pdb(KindleTestFiles.header(8, KindleTestFiles.exth(122, "true".getBytes(StandardCharsets.US_ASCII))), KindleTestFiles.TEXT);
        assertTrue(reject(fixed).getMessage().contains("固定版式"));
        byte[] replica = KindleTestFiles.pdb(KindleTestFiles.header(6), "%MOPpayload".getBytes(StandardCharsets.US_ASCII));
        assertTrue(reject(replica).getMessage().contains("Print Replica"));
        File reflow = file(KindleTestFiles.pdb(KindleTestFiles.header(8, KindleTestFiles.exth(122, "false".getBytes(StandardCharsets.US_ASCII))), KindleTestFiles.TEXT));
        assertEquals(KindleContainer.Mode.KF8, KindleContainer.inspect(reflow, ComicArchive.NEVER).mode);
    }
    @Test public void cancellationAndOversizeStopWithoutReadingOrChangingSource() throws Exception {
        File file = file(KindleTestFiles.mixed()); byte[] before = Files.readAllBytes(file.toPath()); int[] checks = {0};
        assertThrows(IOException.class, () -> KindleContainer.inspect(file, () -> ++checks[0] > 3));
        assertArrayEquals(before, Files.readAllBytes(file.toPath()));
        File huge = folder.newFile(); try (RandomAccessFile output = new RandomAccessFile(huge, "rw")) { output.setLength(ComicArchive.MAX_SOURCE + 1); }
        assertTrue(assertThrows(IOException.class, () -> KindleContainer.inspect(huge, ComicArchive.NEVER)).getMessage().contains("1 GiB"));
    }
    @Test public void changedSourceDoesNotProduceAReusableInspectionResult() throws Exception {
        File file = file(KindleTestFiles.single(6)); long modified = file.lastModified(); int[] checks = {0};
        IOException failure = assertThrows(IOException.class, () -> KindleContainer.inspect(file, () -> {
            if (++checks[0] == 3) assertTrue(file.setLastModified(modified + 10_000)); return false;
        }));
        assertTrue(failure.getMessage().contains("改变"));
    }
    @Test public void cancellationDuringValidationNeverPublishesOrLeavesPartialCopy() throws Exception {
        File input=file(KindleTestFiles.mixed()),directory=folder.newFolder();List<Book> published=new ArrayList<>();
        java.util.concurrent.atomic.AtomicReference<BookImportController<File>> owner=new java.util.concurrent.atomic.AtomicReference<>();
        BookImportController<File> controller=new BookImportController<>(directory,new BookImportController.Source<File>() {
            public String name(File file){return "test.AZW3";}
            public InputStream open(File file)throws Exception{return new FileInputStream(file);}
            public void validate(File file,String format,ComicArchive.Cancellation cancel)throws Exception{owner.get().close();DocumentFormats.validate(null,file,format,cancel);}
        },Runnable::run,Runnable::run,new BookImportController.Listener(){
            public void changed(){} public void publish(Book book){published.add(book);}
            public void finished(int added,int duplicate,int failed){fail("closed import must not publish completion");}
        });
        owner.set(controller);controller.importBooks(List.of(input),List.of());
        assertTrue(published.isEmpty());assertEquals(0,Objects.requireNonNull(directory.list()).length);
        assertArrayEquals(KindleTestFiles.mixed(),Files.readAllBytes(input.toPath()));
    }
}
