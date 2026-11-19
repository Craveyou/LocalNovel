package com.xlib.txtreader;

import static org.junit.Assert.*;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Base64;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.KeyStore;
import java.security.cert.CertificateFactory;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import javax.net.ssl.*;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;

/** Separate Android processes share one disposable service with a real iOS client. */
@RunWith(AndroidJUnit4.class)
public class CrossComicInteropDeviceTest {
    private static final String DEVICE = "01410000-0000-4000-8000-000000000001";
    private static final String[] ORIGINALS = {"comic-basic.cbz", "comic-basic-rar4.cbr",
            "comic-basic-rar5.cbr", "comic-basic-rar4-solid.cbr"};
    private final Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
    private String run, token;
    private SyncApiClient api;

    private void waitFor(BooleanSupplier condition) throws Exception {
        long end = SystemClock.uptimeMillis() + 15_000;
        while (!condition.getAsBoolean() && SystemClock.uptimeMillis() < end) Thread.sleep(25);
        assertTrue("Cross-client Android session timed out", condition.getAsBoolean());
    }
    private byte[] asset(String name) throws Exception {
        try (InputStream input = InstrumentationRegistry.getInstrumentation().getContext()
                .getAssets().open("documents/" + name); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] bytes = new byte[65536]; int count;
            while ((count = input.read(bytes)) != -1) output.write(bytes, 0, count);
            return output.toByteArray();
        }
    }
    private String path(Book book, String hash) { return "/v2/progress/" + hash + "/" + book.fileSize; }
    private JSONArray remote(Book book, String hash) throws Exception {
        return api.requestJson("GET", path(book, hash), null, token, DEVICE).getJSONArray("items");
    }
    private JSONObject onlyRemote(Book book, String hash) throws Exception {
        JSONArray items = remote(book, hash); assertEquals(1, items.length()); return items.getJSONObject(0);
    }
    private DocumentSyncSession.Connection connection(AtomicInteger posts) {
        return new DocumentSyncSession.Connection() {
            public boolean enabled() { return true; }
            public String identity() { return run + "\n" + DEVICE + "\n" + token; }
            public JSONObject get(String path) throws Exception { return api.requestJson("GET", path, null, token, DEVICE); }
            public JSONObject post(JSONObject body) throws Exception {
                JSONObject response = api.requestJson("POST", "/v2/progress/sync", body, token, DEVICE);
                posts.incrementAndGet(); return response;
            }
            public void delete(String path) throws Exception { api.requestNoContent("DELETE", path, token, DEVICE); }
        };
    }
    private DocumentSyncSession session(LocalDatabase db, Book book, String hash, ComicManifest manifest,
                                        AtomicInteger posts, AtomicInteger prompts, DocumentLocator expected, long time) {
        DocumentSyncSession session = new DocumentSyncSession(book, hash, new DocumentSyncSession.Listener() {
            public void state(String text) { }
            public void remote(DocumentLocator locator, long readAt, Runnable accepted, Runnable rejected) {
                if (expected == null || !expected.equals(locator) || readAt != time) { rejected.run(); return; }
                // The same typed persistence boundary used by ComicPreviewActivity;
                // accepting a peer must retain its exact reading timestamp.
                db.saveDocumentPosition(book, locator, hash, readAt);
                accepted.run(); prompts.incrementAndGet();
            }
        }, connection(posts));
        session.validateWith(value -> manifest.valid(value, book.format));
        return session;
    }
    private void upload(DocumentSyncSession session, AtomicInteger posts) throws Exception {
        session.resume();
        waitFor(() -> { session.refresh(); return posts.get() == 1; });
    }
    private Book importOriginal(LocalDatabase db, String name) throws Exception {
        File input = File.createTempFile("cross-comic-", ".original", context.getCacheDir());
        Files.write(input.toPath(), asset(name));
        List<Book> published = new ArrayList<>();
        try {
            BookImportController<File> imports = new BookImportController<>(new File(context.getFilesDir(), "books"),
                    new BookImportController.Source<File>() {
                        public String name(File file) { return name; }
                        public InputStream open(File file) throws Exception { return new FileInputStream(file); }
                        public void validate(File file, String format, ComicArchive.Cancellation cancel) throws Exception {
                            DocumentFormats.validate(context, file, format, cancel);
                        }
                    }, Runnable::run, Runnable::run, new BookImportController.Listener() {
                        public void changed() { }
                        public void publish(Book book) { published.add(book); }
                        public void finished(int added, int duplicates, int failed) {
                            assertEquals(1, added); assertEquals(0, duplicates); assertEquals(0, failed);
                        }
                    });
            imports.importBooks(Collections.singletonList(input), Collections.emptyList()); imports.close();
            assertEquals(1, published.size()); Book book = published.get(0);
            assertArrayEquals(asset(name), Files.readAllBytes(new File(book.path).toPath()));
            List<Book> books = db.loadBooks(); books.add(book); assertTrue(db.saveBooks(books, null, 0, 0));
            return book;
        } finally { input.delete(); }
    }
    private Book load(LocalDatabase db, JSONObject record) throws Exception {
        for (Book book : db.loadBooks()) if (book.id == record.getLong("bookId")) return book;
        throw new AssertionError("Seeded Android book missing; run seed on this emulator first");
    }
    private JSONObject assertion(Book book, String hash, JSONObject state) throws Exception {
        return new JSONObject().put("bookHash", hash).put("fileSize", book.fileSize)
                .put("localLocator", book.locator.json()).put("localReadAtMs", book.updatedAt)
                .put("remote", state == null ? JSONObject.NULL : state);
    }
    private void checkManifestRejection(Book book, String hash, JSONObject current) throws Exception {
        JSONObject bad = new JSONObject().put("bookHash", hash).put("fileSize", book.fileSize)
                .put("locator", new JSONObject(current.getJSONObject("locator").toString()));
        bad.getJSONObject("locator").put("manifestHash", "0".repeat(64));
        for (long time : new long[]{current.getLong("readAtMs") - 1000, current.getLong("readAtMs") + 1000}) {
            bad.put("readAtMs", time);
            SyncApiClient.ApiException error = assertThrows(SyncApiClient.ApiException.class,
                    () -> api.requestJson("POST", "/v2/progress/sync",
                            new JSONObject().put("items", new JSONArray().put(bad)), token, DEVICE));
            assertEquals(422, error.status);
            assertEquals("Rejected manifest cannot replace the iOS row", current.toString(), onlyRemote(book, hash).toString());
        }
    }
    private void decode(ComicDocument document, int page) throws Exception {
        Bitmap image = document.page(page, 1080, ComicArchive.NEVER); assertNotNull(image); image.recycle();
    }

    @Test public void stagedAndroidIOSComicContinuation() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        String base = args.getString("interopUrl"), stage = args.getString("interopStage");
        Assume.assumeNotNull(base, stage);
        assertTrue(base.matches("https://localhost:[0-9]+"));
        assertTrue(Arrays.asList("seed", "accept-ios", "verify-deleted").contains(stage));
        assertTrue(android.os.Build.HARDWARE.contains("ranchu") || android.os.Build.HARDWARE.contains("goldfish"));
        run = args.getString("interopRun"); assertNotNull(run); assertTrue(run.matches("[A-Za-z0-9_-]{1,100}"));
        KeyStore trusted = KeyStore.getInstance(KeyStore.getDefaultType()); trusted.load(null);
        trusted.setCertificateEntry("one-cross-test", CertificateFactory.getInstance("X.509").generateCertificate(
                new ByteArrayInputStream(Base64.decode(args.getString("interopCertificate"), Base64.DEFAULT))));
        TrustManagerFactory managers = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()); managers.init(trusted);
        SSLContext ssl = SSLContext.getInstance("TLS"); ssl.init(null, managers.getTrustManagers(), null);
        SSLSocketFactory previous = HttpsURLConnection.getDefaultSSLSocketFactory();
        HttpsURLConnection.setDefaultSSLSocketFactory(ssl.getSocketFactory());
        File stateFile = new File(context.getFilesDir(), "cross-comic-" + run + ".json");
        try (LocalDatabase db = LocalDatabase.open(context, context.getSharedPreferences("xlib_reader", 0))) {
            api = new SyncApiClient(base);
            token = api.startSync(run + "-cross-comic@example.com", DEVICE, "Android cross comic", "0.13.1").token;
            JSONArray records = "seed".equals(stage) ? new JSONArray()
                    : new JSONObject(new String(Files.readAllBytes(stateFile.toPath()), StandardCharsets.UTF_8)).getJSONArray("books");
            if (!"seed".equals(stage)) assertEquals(4, records.length());
            JSONArray evidence = new JSONArray();
            for (int index = 0; index < ORIGINALS.length; index++) {
                String name = ORIGINALS[index]; Book book = "seed".equals(stage) ? importOriginal(db, name) : load(db, records.getJSONObject(index));
                String hash = new BookHashCache(db).resolve(book.id, new File(book.path)).bookHash;
                JSONObject fixture = new JSONObject(new String(asset(name.replace(".cbz", ".json").replace(".cbr", ".json")), StandardCharsets.UTF_8));
                assertEquals(fixture.getString("bookHash"), hash); assertEquals(fixture.getLong("fileSize"), book.fileSize);
                File scratch = Files.createTempDirectory(context.getCacheDir().toPath(), "cross-decode-").toFile();
                try (ComicDocument document = new ComicDocument(new File(book.path), scratch, ComicArchive.NEVER)) {
                    ComicManifest manifest = document.manifest;
                    assertEquals(fixture.getString("manifestHash"), manifest.hash); assertEquals(24, document.pageCount);
                    AtomicInteger posts = new AtomicInteger(), prompts = new AtomicInteger();
                    if ("seed".equals(stage)) {
                        assertEquals(0, remote(book, hash).length()); document.validate(ComicArchive.NEVER); decode(document, 10);
                        long seedTime = System.currentTimeMillis() - 10_000;
                        db.saveDocumentPosition(book, manifest.locator(book.format, 10, .234567), hash, seedTime);
                        assertTrue(db.addDocumentBookmark(book.id, book.locator));
                        try (DocumentSyncSession session = session(db, book, hash, manifest, posts, prompts, null, 0)) {
                            upload(session, posts);
                            JSONObject state = onlyRemote(book, hash);
                            assertEquals(book.locator, DocumentLocator.fromJson(state.getJSONObject("locator")));
                            assertEquals(seedTime, state.getLong("readAtMs")); assertEquals("android", state.getJSONObject("device").getString("platform"));
                            evidence.put(assertion(book, hash, state));
                        }
                        records.put(new JSONObject().put("bookId", book.id).put("name", name).put("seedReadAtMs", seedTime));
                    } else if ("accept-ios".equals(stage)) {
                        JSONObject ios = onlyRemote(book, hash); long iosTime = ios.getLong("readAtMs");
                        assertEquals("ios", ios.getJSONObject("device").getString("platform"));
                        assertNotEquals(DEVICE, ios.getJSONObject("device").getString("deviceId"));
                        DocumentLocator expected = manifest.locator(book.format, 11, 0);
                        assertEquals(expected, DocumentLocator.fromJson(ios.getJSONObject("locator")));
                        assertTrue(iosTime > records.getJSONObject(index).getLong("seedReadAtMs"));
                        assertEquals(records.getJSONObject(index).getLong("seedReadAtMs"), book.updatedAt);
                        checkManifestRejection(book, hash, ios); decode(document, 11);
                        try (DocumentSyncSession session = session(db, book, hash, manifest, posts, prompts, expected, iosTime)) {
                            session.resume(); waitFor(() -> prompts.get() == 1);
                            assertEquals(expected, book.locator); assertEquals(iosTime, book.updatedAt); assertEquals(0, posts.get());
                            Book persisted = load(db, records.getJSONObject(index));
                            assertEquals(expected, persisted.locator); assertEquals(iosTime, persisted.updatedAt);
                            JSONObject proof = assertion(book, hash, ios).put("acceptancePostCount", posts.get());
                            // Move backward in content with a later actual reading event.
                            decode(document, 10);
                            db.saveDocumentPosition(book, manifest.locator(book.format, 10, .500001), hash,
                                    SyncRules.monotonicReadAt(System.currentTimeMillis(), iosTime));
                            session.moved(); waitFor(() -> { session.refresh(); return posts.get() == 1; });
                            JSONObject uploaded = onlyRemote(book, hash);
                            assertEquals(book.locator, DocumentLocator.fromJson(uploaded.getJSONObject("locator")));
                            assertEquals(book.updatedAt, uploaded.getLong("readAtMs")); assertTrue(book.updatedAt > iosTime);
                            assertEquals("android", uploaded.getJSONObject("device").getString("platform"));
                            evidence.put(proof.put("androidReturn", uploaded));
                        }
                    } else {
                        // iOS must have deleted all four rows after accepting Android's backward move.
                        assertEquals(0, remote(book, hash).length());
                        assertEquals(manifest.locator(book.format, 10, .500001), book.locator);
                        assertEquals(1, db.documentBookmarks(book.id).size());
                        // Read-only verification: a newly resumed formal session
                        // would legitimately upload its local position again.
                        evidence.put(assertion(book, hash, null).put("postCount", 0).put("readOnly", true));
                    }
                } finally { scratch.delete(); }
                assertArrayEquals(asset(name), Files.readAllBytes(new File(book.path).toPath()));
            }
            JSONObject state = new JSONObject().put("run", run).put("stage", stage).put("deviceId", DEVICE).put("books", records);
            Files.write(stateFile.toPath(), state.toString(2).getBytes(StandardCharsets.UTF_8));
            JSONObject report = new JSONObject().put("run", run).put("stage", stage).put("platform", "android")
                    .put("deviceId", DEVICE).put("versionCode", context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionCode).put("books", evidence);
            Files.write(new File(context.getExternalFilesDir(null), "cross-comic-" + run + "-" + stage + ".json").toPath(),
                    report.toString(2).getBytes(StandardCharsets.UTF_8));
            assertTrue("No v1 comic rows", api.pullProgress(token, DEVICE).isEmpty());
        } finally { HttpsURLConnection.setDefaultSSLSocketFactory(previous); }
    }
}
