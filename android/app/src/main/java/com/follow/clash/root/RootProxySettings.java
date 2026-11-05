package com.follow.clash.root;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class RootProxySettings {
    interface Command {
        String run(String... arguments) throws Exception;
    }

    private final Command command;

    RootProxySettings() {
        this(RootProxySettings::runCommand);
    }

    RootProxySettings(Command command) {
        this.command = command;
    }

    RootProxyState.Value read() throws Exception {
        String host = get("global_http_proxy_host");
        String pac = get("global_proxy_pac_url");
        String portValue = get("global_http_proxy_port");
        int port = 0;
        if (!portValue.isEmpty()) port = Integer.parseInt(portValue);
        String exclusions = get("global_http_proxy_exclusion_list");
        return RootProxyState.value(host, port, Arrays.asList(exclusions.split(",")), pac);
    }

    void write(RootProxyState.Value target) throws Exception {
        put("global_http_proxy_host", target == null ? "" : target.host);
        put("global_http_proxy_port", Integer.toString(target == null ? 0 : target.port));
        put("global_http_proxy_exclusion_list", target == null ? "" : String.join(",", target.exclusions));
        put("global_proxy_pac_url", target == null ? "" : target.pac);
    }

    private String get(String key) throws Exception {
        String value = command.run("get", "global", key).trim();
        return "null".equals(value) ? "" : value;
    }

    private void put(String key, String value) throws Exception {
        command.run("put", "global", key, value);
    }

    private static String runCommand(String... arguments) throws Exception {
        List<String> invocation = new ArrayList<>(Arrays.asList("/system/bin/cmd", "settings"));
        invocation.addAll(Arrays.asList(arguments));
        ShellResult result = new RootShell(65537).execute(invocation, 2_000, new byte[0]);
        if (!result.getSuccess() || !result.getStderr().trim().isEmpty()
            || result.getStdout().getBytes(StandardCharsets.UTF_8).length > 65536) {
            throw new IOException("System proxy settings command failed: " + arguments[0] + " " + arguments[2]);
        }
        return result.getStdout();
    }
}
