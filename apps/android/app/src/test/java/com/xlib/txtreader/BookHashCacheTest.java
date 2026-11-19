package com.xlib.txtreader;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class BookHashCacheTest {
    @Rule public TemporaryFolder folder = new TemporaryFolder();
    private final LocalDatabase database = mock(LocalDatabase.class);
    private File source(int bytes) throws Exception {
        File file = folder.newFile(); Files.write(file.toPath(), new byte[bytes]); return file;
    }
    @Test public void cancelBeforeCacheReadAndAfterCacheHitDoesNotReturnResult() throws Exception {
        File file = source(1); BookHashCache hashes = new BookHashCache(database);
        assertThrows(IOException.class, () -> hashes.resolve(7, file, () -> true));
        verifyNoInteractions(database);
        when(database.readHash(7)).thenReturn(new BookHashCache.HashResult("cached", 1, file.lastModified()));
        AtomicInteger checks = new AtomicInteger();
        assertThrows(IOException.class, () -> hashes.resolve(7, file, () -> checks.incrementAndGet() == 2));
        verify(database, never()).writeHash(anyLong(), any());
    }
    @Test public void cancelDuringLargeFileHashLeavesSourceAndExistingCacheUntouched() throws Exception {
        File file = source(1024 * 1024); long modified = file.lastModified();
        BookHashCache.HashResult old = new BookHashCache.HashResult("old", 0, 0);
        when(database.readHash(7)).thenReturn(old); AtomicInteger checks = new AtomicInteger();
        assertThrows(IOException.class, () -> new BookHashCache(database).resolve(7, file, () -> checks.incrementAndGet() >= 5));
        assertEquals(5, checks.get()); assertEquals(1024 * 1024, file.length()); assertEquals(modified, file.lastModified());
        assertArrayEquals(new byte[1024 * 1024], Files.readAllBytes(file.toPath()));
        verify(database, never()).writeHash(anyLong(), any()); verify(database, never()).removeHash(anyLong());
    }
    @Test public void cancelBeforePublishingDigestDoesNotWriteCache() throws Exception {
        File file = source(1); AtomicInteger checks = new AtomicInteger();
        assertThrows(IOException.class, () -> new BookHashCache(database).resolve(7, file, () -> checks.incrementAndGet() == 4));
        verify(database, never()).writeHash(anyLong(), any());
    }
    @Test public void successfulHashIsSha256AndUnchangedCacheIsReused() throws Exception {
        File file = folder.newFile(); Files.write(file.toPath(), new byte[]{'a','b','c'});
        BookHashCache hashes = new BookHashCache(database); BookHashCache.HashResult result = hashes.resolve(7, file);
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", result.bookHash);
        assertEquals(3, result.fileSize); verify(database).writeHash(7, result);
        when(database.readHash(7)).thenReturn(result); assertSame(result, hashes.resolve(7, file, () -> false));
        verify(database, times(1)).writeHash(anyLong(), any());
    }
}
