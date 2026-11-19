package com.xlib.txtreader;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import java.io.File;
import java.lang.reflect.Field;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class) @Config(sdk=35)
public class ReaderCancellationTest {
    private Field field(String name) throws Exception {
        Field field = ComicPreviewActivity.class.getDeclaredField(name); field.setAccessible(true); return field;
    }
    @Test public void leavingComicReaderCancelsWorkThenClosesDatabaseAndRemovesScratch() throws Exception {
        ComicPreviewActivity activity = Robolectric.buildActivity(ComicPreviewActivity.class).get();
        LocalDatabase database = mock(LocalDatabase.class); field("database").set(activity, database);
        File scratch = new File(activity.getCacheDir(), "cancel-reader-test"); assertTrue(scratch.mkdirs() || scratch.isDirectory());
        assertTrue(new File(scratch, "partial-page").createNewFile()); field("directory").set(activity, scratch);
        ExecutorService worker = (ExecutorService) field("worker").get(activity);
        CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
        worker.execute(() -> { entered.countDown(); try { release.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } });
        assertTrue(entered.await(5, TimeUnit.SECONDS));
        try {
            activity.onDestroy();
            assertTrue(field("destroyed").getBoolean(activity)); assertTrue(worker.isShutdown());
            verify(database, never()).close(); assertTrue(scratch.exists());
        } finally { release.countDown(); }
        assertTrue(worker.awaitTermination(5, TimeUnit.SECONDS)); verify(database).close(); assertFalse(scratch.exists());
    }
}
