package com.xlib.txtreader;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Serial per-open-document sync. Passwords and document text never enter this boundary. */
final class DocumentSyncSession implements AutoCloseable {
    interface Listener {
        void remote(DocumentLocator locator, long time, Runnable accepted, Runnable rejected);
        void state(String text);
    }
    private final ExecutorService network = Executors.newSingleThreadExecutor();
    private final Object lifecycle = new Object();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Book book;
    private final String hash;
    interface Connection {
        boolean enabled();
        String identity() throws Exception;
        JSONObject get(String path) throws Exception;
        JSONObject post(JSONObject body) throws Exception;
        void delete(String path) throws Exception;
        default void blockCredentials() { }
    }
    private final Connection connection;
    private final Listener listener;
    private volatile boolean active, closed, temporary, paused, preparing, busy, awaitingChoice, deleting, comparisonRequired = true;
    private volatile int generation;
    private volatile String message = "未开启同步，可继续本地阅读";
    private volatile boolean refreshRequested;
    private String promptedVersion;
    private final Runnable periodic = new Runnable() { public void run() { refresh(); if (active && !closed) main.postDelayed(this, 20_000); } };

    DocumentSyncSession(Context context, LocalDatabase database, Book book, String hash, Listener listener) {
        this(book, hash, listener, new Connection() {
            final SyncTokenStore tokens = new SyncTokenStore(context.getSharedPreferences("xlib_reader", Context.MODE_PRIVATE), database);
            final SyncServerConfig config = new SyncServerConfig(database);
            public boolean enabled() { return tokens.enabled(); }
            public String identity() throws Exception {
                String token = tokens.token();
                if(token==null || !tokens.activeConfigurationMatches(config.url())) throw new IllegalStateException();
                return config.url()+"\n"+tokens.deviceId()+"\n"+token;
            }
            public JSONObject get(String path) throws Exception { return new SyncApiClient(config.url()).requestJson("GET",path,null,tokens.token(),tokens.deviceId()); }
            public JSONObject post(JSONObject body) throws Exception { return new SyncApiClient(config.url()).requestJson("POST","/v2/progress/sync",body,tokens.token(),tokens.deviceId()); }
            public void blockCredentials() { tokens.clear(); }
            public void delete(String path) throws Exception { new SyncApiClient(config.url()).requestNoContent("DELETE",path,tokens.token(),tokens.deviceId()); }
        });
    }
    DocumentSyncSession(Book book, String hash, Listener listener, Connection connection) {
        this.book=book; this.hash=hash; this.listener=listener; this.connection=connection;
    }
    interface LocatorValidator {boolean valid(DocumentLocator value);}
    private LocatorValidator validator=value->true;
    void validateWith(LocatorValidator value){validator=value;}
    boolean canRead() { return !preparing; }
    String message() { return message; }
    void temporary(boolean value) { temporary = value; if (!value && active) refresh(); }
    void moved() { if (active && !paused && !preparing) refresh(); }
    void resume() { if (closed || active) return; active = true; comparisonRequired = true; generation++; refresh(); if(active&&!closed)main.postDelayed(periodic, 20_000); }
    void pause() { active = false; generation++; preparing = false; awaitingChoice=false; main.removeCallbacks(periodic); }
    private void state(String value) { message = value; main.post(() -> { if (!closed) listener.state(value); }); }
    private boolean submit(Runnable operation) {
        synchronized(lifecycle){if(closed)return false;network.execute(operation);return true;}
    }
    synchronized void refresh() {
        if (!active || closed || temporary || awaitingChoice || deleting) return;
        if(busy){refreshRequested=true;return;}
        refreshRequested=false;
        if (!connection.enabled()) { preparing = false; state("未开启同步，可在书架设置中开启；本地阅读可用"); return; }
        busy = true; preparing = comparisonRequired; int request = generation;
        if(!submit(() -> {
            try {
                if(!active||closed||request!=generation)return;
                String scope=connection.identity();
                JSONArray items = connection.get(path()).getJSONArray("items");
                if(!scope.equals(connection.identity()))throw new IllegalStateException("配置已变化");
                if(items.length()>1)throw new IllegalArgumentException("远端条目无效");
                JSONObject remote = items.length() == 0 ? null : items.getJSONObject(0);
                DocumentLocator remotePosition = null; long remoteTime = 0;
                if (remote != null) {
                    remotePosition = checkedPosition(remote);
                    remoteTime = remote.getLong("readAtMs");
                    if (remoteTime < 0 || !book.format.equals(remotePosition.format)) throw new IllegalArgumentException("远端定位无效");
                }
                if (!active || closed || request != generation) return;
                DocumentLocator local = book.locator;
                long localTime = book.updatedAt;
                if (remote != null && remoteTime > localTime && !remotePosition.equals(local)
                        && !remote.getString("version").equals(promptedVersion)) {
                    preparing=true; awaitingChoice=true;
                    DocumentLocator target = remotePosition; long time = remoteTime; String version = remote.getString("version");
                    main.post(() -> {
                        if (!active || closed || request != generation) return;
                        // Position may have changed while the request was in flight.
                        if (book.updatedAt >= time) { preparing = false; awaitingChoice=false; return; }
                        listener.remote(target, time, () -> { if(!active||closed||request!=generation)return; awaitingChoice=false; promptedVersion = version; comparisonRequired = false; preparing = false; state("已采用远端位置"); },
                                () -> { if(!active||closed||request!=generation)return; awaitingChoice=false; promptedVersion = version; comparisonRequired = false; preparing = false; state("已保留当前阅读位置"); });
                    });
                    return;
                }
                preparing = false; comparisonRequired = false;
                if (!paused && !temporary && active && request == generation && localTime > 0
                        && (remote == null || localTime > remoteTime)) {
                    JSONObject item = new JSONObject().put("bookHash", hash).put("fileSize", book.fileSize)
                            .put("locator", local.json()).put("readAtMs", localTime);
                    if(!scope.equals(connection.identity()))throw new IllegalStateException("配置已变化");
                    JSONObject response = connection.post(new JSONObject().put("items", new JSONArray().put(item)));
                    JSONArray results=response.getJSONArray("results");
                    if(results.length()!=1)throw new IllegalArgumentException("响应条数无效");
                    checkedPosition(results.getJSONObject(0).getJSONObject("state"));
                }
                state(paused ? "本次阅读已暂停上传；关闭重开后恢复" : "同步比较完成");
            } catch (Exception error) { if(request==generation){ preparing = false; awaitingChoice=false; comparisonRequired = true;
                if(error instanceof SyncApiClient.ApiException && (((SyncApiClient.ApiException)error).status==401 || ((SyncApiClient.ApiException)error).status==403)){
                    connection.blockCredentials();state("同步凭据失效，请返回书架重新开启；本地阅读可用");
                }else state("同步暂不可用，保留本地阅读；可刷新重试"); } }
            finally { busy = false; if(active&&!closed&&(refreshRequested||request!=generation))main.post(this::refresh); }
        })){busy=false;preparing=false;}
    }
    private String path() { return "/v2/progress/" + hash + "/" + book.fileSize; }
    private void checkIdentity(JSONObject state) throws Exception {
        Object size=state.get("fileSize");
        if (!(size instanceof Number) || ((Number)size).doubleValue()!=book.fileSize || !hash.equals(state.getString("bookHash")))
            throw new IllegalArgumentException("远端文档身份不匹配");
    }
    private DocumentLocator checkedPosition(JSONObject state) throws Exception {
        checkIdentity(state);
        DocumentLocator position=DocumentLocator.fromJson(state.getJSONObject("locator"));
        if(!validator.valid(position))throw new IllegalArgumentException("远端清单与本地原包不匹配");
        Object time=state.get("readAtMs"), fraction=state.get("progress"), version=state.get("version");
        if(!(time instanceof Number)||((Number)time).doubleValue()<0 || ((Number)time).doubleValue()>253_402_300_799_999d
                || ((Number)time).doubleValue()!=((Number)time).longValue() || !(fraction instanceof Number)
                || !Double.isFinite(((Number)fraction).doubleValue())
                || Math.abs(((Number)fraction).doubleValue()-position.progress())>0.000001
                || !(version instanceof String)||((String)version).isEmpty()||!book.format.equals(position.format))throw new IllegalArgumentException("远端定位无效");
        JSONObject device=state.getJSONObject("device");
        if(!device.getString("deviceId").matches("(?i)[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")
                || device.getString("deviceName").isEmpty()||device.getString("deviceName").length()>80
                || !java.util.Arrays.asList("android","ios","macos").contains(device.getString("platform")))throw new IllegalArgumentException("来源设备无效");
        return position;
    }
    void delete() {
        if (closed || !active || deleting) return;
        deleting=true; generation++;awaitingChoice=false;preparing=false;
        if(!submit(() -> {
            try {
                connection.identity();
                connection.delete(path());
                paused = true; preparing = false; deleting=false; state("云端进度已删除，本次阅读暂停上传");
            } catch (Exception e) { deleting=false; state("删除失败，本地数据保留"); }
            finally { deleting=false; }
        })){deleting=false;}
    }
    @Override public void close() { synchronized(lifecycle){pause();closed=true;network.shutdown();}main.removeCallbacksAndMessages(null); }
}
