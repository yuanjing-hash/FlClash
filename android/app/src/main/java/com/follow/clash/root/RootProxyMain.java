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

    public static void main(String[] args) {
        try {
            if (android.os.Process.myUid() != 0 || args.length != 1) throw new IllegalStateException("Root required");
            if (android.os.Looper.myLooper() == null) android.os.Looper.prepareMainLooper();
            Class<?> activityThread = Class.forName("android.app.ActivityThread");
            Object thread = activityThread.getMethod("systemMain").invoke(null);
            Context context = (Context) activityThread.getMethod("getSystemContext").invoke(thread);
            if ("prepare".equals(args[0])) {
                prepare(context);
                System.exit(0);
            }
            ConnectivityManager manager = context.getSystemService(ConnectivityManager.class);
            ProxyInfo current = (ProxyInfo) ConnectivityManager.class.getMethod("getGlobalProxy").invoke(manager);
            File state = new File(BASE, "state/proxy.json");
            ProxyInfo replacement;
            if ("apply".equals(args[0])) {
                String address = new String(Files.readAllBytes(new File(BASE, "config/system-proxy").toPath()), StandardCharsets.UTF_8).trim();
                if (address.isEmpty()) return;
                String exclusions = new String(Files.readAllBytes(new File(BASE, "config/proxy-exclusions").toPath()), StandardCharsets.UTF_8);
                replacement = ProxyInfo.buildDirectProxy("127.0.0.1", Integer.parseInt(address.substring(address.lastIndexOf(':') + 1)),
                    exclusions.isEmpty() ? new ArrayList<>() : Arrays.asList(exclusions.split(",")));
                JSONObject snapshot = new JSONObject().put("previous", encode(current)).put("applied", encode(replacement));
                File temporary = new File(state.getPath() + ".tmp");
                Files.write(temporary.toPath(), snapshot.toString().getBytes(StandardCharsets.UTF_8));
                Files.move(temporary.toPath(), state.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            } else if ("restore".equals(args[0])) {
                if (!state.isFile()) return;
                JSONObject snapshot = new JSONObject(new String(Files.readAllBytes(state.toPath()), StandardCharsets.UTF_8));
                ProxyInfo applied = decode(snapshot.getJSONObject("applied"));
                if (current == null || !current.equals(applied)) {
                    Files.deleteIfExists(state.toPath());
                    return;
                }
                replacement = decode(snapshot.getJSONObject("previous"));
            } else {
                throw new IllegalArgumentException("Unknown proxy operation");
            }
            ConnectivityManager.class.getMethod("setGlobalProxy", ProxyInfo.class).invoke(manager, replacement);
            if ("restore".equals(args[0])) Files.deleteIfExists(state.toPath());
            System.exit(0);
        } catch (Exception error) {
            System.err.println("phase=root/" + (args.length == 1 ? args[0] : "helper") + ": " + error);
            System.exit(1);
        }
    }
}
