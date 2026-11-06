package com.follow.clash.root;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.ProxyInfo;
import android.net.Uri;
import android.system.Os;
import android.util.Xml;

import com.follow.clash.models.SharedState;
import com.google.gson.Gson;
import com.google.gson.JsonObject;

import org.xmlpull.v1.XmlPullParser;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

public final class RootProxyMain {
    private static final File BASE = new File("/data/adb/flclash-root");

    private static void write(File target, String value) throws Exception {
        File temporary = new File(target.getPath() + ".tmp");
        Files.write(temporary.toPath(), value.getBytes(StandardCharsets.UTF_8));
        Os.chmod(temporary.getPath(), 0600);
        Files.move(temporary.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    }

    private static void prepare(Context context) throws Exception {
        Gson gson = new Gson();
        File target = new File(BASE, "config/root-core.json");
        JsonObject launch = gson.fromJson(new String(Files.readAllBytes(target.toPath()), StandardCharsets.UTF_8), JsonObject.class);
        File home = new File(launch.getAsJsonObject("init").get("home-dir").getAsString()).getCanonicalFile();
        int appUid = launch.get("appUid").getAsInt();
        if (appUid < 10000 || !"files".equals(home.getName()) || Os.stat(home.getPath()).st_uid != appUid) {
            throw new IllegalStateException("App home owner mismatch");
        }
        File preferences = new File(home.getParentFile(), "shared_prefs/FlutterSharedPreferences.xml");
        if (preferences.length() > 16 * 1024 * 1024) throw new IllegalStateException("Shared state exceeds size limit");
        String json = null;
        try (FileInputStream input = new FileInputStream(preferences)) {
            XmlPullParser parser = Xml.newPullParser();
            parser.setInput(input, "UTF-8");
            for (int event = parser.getEventType(); event != XmlPullParser.END_DOCUMENT; event = parser.next()) {
                if (event == XmlPullParser.START_TAG && "string".equals(parser.getName())
                    && "flutter.sharedState".equals(parser.getAttributeValue(null, "name"))) {
                    json = parser.nextText();
                    break;
                }
            }
        }
        if (json == null) throw new IllegalStateException("Saved UI state is unavailable");
        int userOffset = appUid / 100000 * 100000;
        Map<String, String> packages = new HashMap<>();
        for (android.content.pm.ApplicationInfo info : context.getPackageManager().getInstalledApplications(0)) {
            packages.put(Integer.toString(userOffset + info.uid % 100000), info.packageName);
        }
        RootPreparedSettings prepared = RootLaunchConfig.INSTANCE.prepare(gson.fromJson(json, SharedState.class), appUid,
            name -> {
                try {
                    return userOffset + context.getPackageManager().getApplicationInfo(name, 0).uid % 100000;
                } catch (android.content.pm.PackageManager.NameNotFoundException missing) {
                    return null;
                }
            }, packages, RootLaunchConfig.INSTANCE.systemDns(context));
        for (Map.Entry<String, Object> entry : prepared.getLaunch().entrySet()) {
            launch.add(entry.getKey(), gson.toJsonTree(entry.getValue()));
        }
        for (Map.Entry<String, String> entry : prepared.getFiles().entrySet()) {
            write(new File(BASE, "config/" + entry.getKey()), entry.getValue());
        }
        write(target, launch.toString());
    }

    private static ProxyInfo decode(JSONObject value) {
        if (value.optBoolean("empty")) return null;
        String pac = value.optString("pac");
        if (!pac.isEmpty()) return ProxyInfo.buildPacProxy(Uri.parse(pac));
        ArrayList<String> exclusions = new ArrayList<>();
        JSONArray list = value.optJSONArray("exclusions");
        if (list != null) for (int i = 0; i < list.length(); i++) exclusions.add(list.optString(i));
        return ProxyInfo.buildDirectProxy(value.optString("host"), value.optInt("port"), exclusions);
    }

    private static JSONObject encode(ProxyInfo proxy) throws Exception {
        JSONObject value = new JSONObject();
        if (proxy == null) return value.put("empty", true);
        return value.put("host", proxy.getHost()).put("port", proxy.getPort())
            .put("exclusions", new JSONArray(Arrays.asList(proxy.getExclusionList())))
            .put("pac", proxy.getPacFileUrl().toString());
    }

    private static RootProxyState.Value value(ProxyInfo proxy) {
        if (proxy == null) return null;
        return RootProxyState.value(proxy.getHost(), proxy.getPort(), Arrays.asList(proxy.getExclusionList()), proxy.getPacFileUrl().toString());
    }

    private static ProxyInfo proxy(RootProxyState.Value value) {
        if (value == null) return null;
        return value.pac.isEmpty() ? ProxyInfo.buildDirectProxy(value.host, value.port, value.exclusions)
            : ProxyInfo.buildPacProxy(Uri.parse(value.pac));
    }

    private static RootProxyState.Value legacyValue(String address) {
        if (address == null || address.isEmpty()) return null;
        int colon = address.lastIndexOf(':');
        if (colon <= 0) return null;
        try {
            int port = Integer.parseInt(address.substring(colon + 1));
            return port > 0 && port <= 65535 ? new RootProxyState.Value(address.substring(0, colon), port, new ArrayList<>(), "") : null;
        } catch (NumberFormatException error) {
            return null;
        }
    }

    private static RootProxyState.Value configuredProxy() throws Exception {
        File address = new File(BASE, "config/system-proxy");
        if (!address.isFile() || address.length() == 0) return null;
        String endpoint = new String(Files.readAllBytes(address.toPath()), StandardCharsets.UTF_8).trim();
        RootProxyState.Value candidate = legacyValue(endpoint);
        if (candidate == null || !"127.0.0.1".equals(candidate.host)) return null;
        File exclusionsFile = new File(BASE, "config/proxy-exclusions");
        if (!exclusionsFile.isFile()) return null;
        String exclusions = new String(Files.readAllBytes(exclusionsFile.toPath()), StandardCharsets.UTF_8);
        return new RootProxyState.Value(candidate.host, candidate.port, Arrays.asList(exclusions.split(",")), "");
    }

    private static boolean ownsLaunchConfig(Context context) throws Exception {
        if (!new File(BASE, "state/session").isFile() || !new File(BASE, "config/app.package").isFile()
            || !new File(BASE, "config/app.uid").isFile()) return false;
        String owner = new String(Files.readAllBytes(new File(BASE, "config/app.package").toPath()), StandardCharsets.UTF_8).trim();
        int uid = Integer.parseInt(new String(Files.readAllBytes(new File(BASE, "config/app.uid").toPath()), StandardCharsets.UTF_8).trim());
        return "com.follow.clash.root".equals(owner) && uid >= 10000
            && uid % 100000 == context.getPackageManager().getApplicationInfo(owner, 0).uid % 100000;
    }

    private static void flushDns(Context context) throws Exception {
        boolean modern = android.os.Build.VERSION.SDK_INT >= 29;
        Object binder = Class.forName("android.os.ServiceManager").getMethod("getService", String.class)
            .invoke(null, modern ? "dnsresolver" : "netd");
        ConnectivityManager manager = context.getSystemService(ConnectivityManager.class);
        RootDnsCache cache;
        if (modern) {
            cache = new RootDnsCache((android.os.IBinder) binder);
        } else {
            String type = "android.net.INetd";
            Object resolver = Class.forName(type + "$Stub").getMethod("asInterface", android.os.IBinder.class)
                .invoke(null, binder);
            java.lang.reflect.Method flush = Class.forName(type).getMethod("resolverFlushCacheForNet", int.class);
            cache = new RootDnsCache(networkId -> flush.invoke(resolver, networkId));
        }
        int[] networkIds = Arrays.stream(manager.getAllNetworks())
            .mapToInt(network -> (int) (network.getNetworkHandle() >>> 32)).toArray();
        cache.flush(networkIds);
    }

    public static void main(String[] args) {
        try {
            if (android.os.Process.myUid() != 0 || args.length != 1) throw new IllegalStateException("Root required");
            File state = new File(BASE, "state/proxy.json");
            if ("restore".equals(args[0]) && !state.isFile() && new File(BASE, "config/system-proxy").length() == 0) return;
            if (android.os.Looper.myLooper() == null) android.os.Looper.prepareMainLooper();
            Class<?> activityThread = Class.forName("android.app.ActivityThread");
            Object thread = activityThread.getMethod("systemMain").invoke(null);
            Context context = (Context) activityThread.getMethod("getSystemContext").invoke(thread);
            if ("flush-dns".equals(args[0])) {
                flushDns(context);
                System.exit(0);
            }
            if ("prepare".equals(args[0])) {
                prepare(context);
                System.exit(0);
            }
            ConnectivityManager manager = context.getSystemService(ConnectivityManager.class);
            if (!"restore".equals(args[0])) throw new IllegalArgumentException("Root TUN does not install a global HTTP proxy");
            RootProxyState.Lease lease = null;
            if (state.isFile()) {
                JSONObject saved = new JSONObject(new String(Files.readAllBytes(state.toPath()), StandardCharsets.UTF_8));
                lease = new RootProxyState.Lease(value(decode(saved.getJSONObject("previous"))), value(decode(saved.getJSONObject("applied"))));
            }
            RootProxyState.Value configured = lease == null ? configuredProxy() : null;
            final RootProxyState.Value applied = lease == null ? (configured != null && ownsLaunchConfig(context) ? configured : null) : lease.applied;
            // app_process has no registered ApplicationThread for Settings' ContentResolver.
            RootProxySettings settings = new RootProxySettings();
            RootProxyState.Backend backend = new RootProxyState.Backend() {
                @Override public RootProxyState.Value cached() throws Exception {
                    return value((ProxyInfo) ConnectivityManager.class.getMethod("getGlobalProxy").invoke(manager));
                }
                @Override public RootProxyState.Value stored() throws Exception { return settings.read(); }
                @Override public void request(RootProxyState.Value target) throws Exception {
                    // Android skips null-to-null requests before updating stored proxy settings.
                    ProxyInfo replacement = target == null ? ProxyInfo.buildDirectProxy("", 0, new ArrayList<>()) : proxy(target);
                    ConnectivityManager.class.getMethod("setGlobalProxy", ProxyInfo.class).invoke(manager, replacement);
                }
                @Override public void repairStored(RootProxyState.Value target) throws Exception { settings.write(target); }
            };
            if (lease == null && applied == null && configured != null && (configured.equals(backend.cached()) || configured.equals(backend.stored()))) {
                throw new IllegalStateException("Legacy proxy ownership could not be verified");
            }
            RootProxyState.Plan plan = RootProxyState.plan(backend.cached(), backend.stored(), lease, applied);
            if (plan.owned && !state.isFile()) {
                write(state, new JSONObject().put("previous", encode(null)).put("applied", encode(proxy(applied)))
                    .put("source", "legacy-launch-config").toString());
            }
            RootProxyState.restore(backend, plan);
            if (state.isFile()) {
                JSONObject completed = new JSONObject(new String(Files.readAllBytes(state.toPath()), StandardCharsets.UTF_8));
                completed.put("owned", plan.owned).put("verified", true)
                    .put("serviceAfter", encode(proxy(backend.cached()))).put("settingsAfter", encode(proxy(backend.stored())));
                write(state, completed.toString());
                Files.move(state.toPath(), new File(BASE, "state/proxy-last-restored.json").toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            }
            System.exit(0);
        } catch (Exception error) {
            System.err.println("phase=root/" + (args.length == 1 ? args[0] : "helper") + ": " + error);
            error.printStackTrace(System.err);
            System.exit(1);
        }
    }
}
