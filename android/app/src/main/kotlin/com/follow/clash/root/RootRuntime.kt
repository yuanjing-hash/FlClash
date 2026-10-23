package com.follow.clash.root

import android.content.Context
import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID

internal class RootRuntime(
    private val context: Context,
) {
    private val shell = RootShell()
    private var controllerPort = 0
    private var controllerToken = ""
    private var stagedBytes = 0L
    var didInstall: Boolean = false
        private set

    fun status(): ShellResult = command("status")

    fun attach(): Boolean {
        val existing = status()
        if (!existing.success || !existing.stdout.startsWith("running")) return false
        val credentials = shell.root("cat $BASE/config/controller.port $BASE/config/health.http")
        val lines = credentials.stdout.lines()
        controllerPort = lines.firstOrNull()?.toIntOrNull() ?: 0
        controllerToken =
            lines
                .firstOrNull { it.startsWith("Authorization: Bearer ") }
                ?.removePrefix("Authorization: Bearer ")
                ?.trim()
                .orEmpty()
        return apiHealthy()
    }

    fun start(
        selections: Map<String, String>,
        allowed: () -> Boolean,
    ) {
        didInstall = false
        if (attach()) return
        check(stop()) { "Previous root runtime could not be cleaned" }
        check(allowed()) { "Start superseded or expired" }
        stagedBytes = 0
        install()
        didInstall = true
        val profile = File(context.filesDir, "config.yaml")
        check(profile.isFile && profile.length() in 1..MAX_CONFIG) { "Active config.yaml is missing or too large" }
        val options =
            LoaderOptions().apply {
                isAllowDuplicateKeys = false
                maxAliasesForCollections = 25
                codePointLimit = MAX_CONFIG.toInt()
                nestingDepthLimit = 64
            }
        val loaded = profile.inputStream().use { Yaml(SafeConstructor(options)).load<Any>(it) }

        @Suppress("UNCHECKED_CAST")
        val config = (loaded as? Map<String, Any?>)?.toMutableMap() ?: error("Active config is not a mapping")

        @Suppress("UNCHECKED_CAST")
        val groups = config["proxy-groups"] as? List<Map<String, Any?>>
        config["proxy-groups"] =
            groups
                ?.map { group ->
                    val selected = selections[group["name"]]
                    val members = group["proxies"] as? List<*>
                    if (group["type"] == "select" && selected != null && members?.contains(selected) == true) {
                        group + ("proxies" to (listOf(selected) + members.filter { it != selected }))
                    } else {
                        group
                    }
                }.orEmpty()
        stagePaths(config)
        listOf("geoip.dat", "geosite.dat", "geoip.metadb", "ASN.mmdb", "Country.mmdb").forEach { name ->
            val asset = File(context.filesDir, name)
            if (asset.isFile) copyAsset(asset, "$BASE/config/$name")
        }
        controllerPort = ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1")).use { it.localPort }
        controllerToken = UUID.randomUUID().toString()
        config.putAll(
            mapOf(
                "external-controller" to "127.0.0.1:$controllerPort",
                "secret" to controllerToken,
                "allow-lan" to false,
                "bind-address" to "127.0.0.1",
                "ipv6" to false,
                "routing-mark" to 1073741824,
                "geo-auto-update" to false,
                "interface-name" to "",
                "find-process-mode" to "off",
                "port" to 0,
                "socks-port" to 0,
                "mixed-port" to 0,
                "redir-port" to 0,
                "tproxy-port" to 0,
                "tun" to
                    mapOf(
                        "enable" to true,
                        "device" to "flcrtun0",
                        "stack" to "gvisor",
                        "mtu" to 1500,
                        "auto-route" to true,
                        "auto-redirect" to false,
                        "auto-detect-interface" to true,
                        "strict-route" to true,
                        "dns-hijack" to listOf("any:53"),
                        "iproute2-table-index" to 2022,
                        "iproute2-rule-index" to 9000,
                    ),
            ),
        )
        listOf(
            "external-controller-tls",
            "external-controller-unix",
            "external-controller-pipe",
            "external-ui",
            "external-ui-url",
            "listeners",
        ).forEach(config::remove)
        @Suppress("UNCHECKED_CAST")
        val dns = (config["dns"] as? Map<String, Any?>)?.toMutableMap() ?: mutableMapOf()
        dns.putAll(mapOf("enable" to true, "ipv6" to false, "listen" to "", "enhanced-mode" to "fake-ip"))
        if (dns["nameserver"] == null) dns["nameserver"] = listOf("https://1.1.1.1/dns-query")
        if (dns["default-nameserver"] == null) dns["default-nameserver"] = listOf("1.1.1.1")
        config["dns"] = dns
        val yaml = Yaml(DumperOptions().apply { defaultFlowStyle = DumperOptions.FlowStyle.BLOCK }).dump(config)
        write("config/config.yaml", yaml.toByteArray())
        write(
            "config/health.http",
            "GET /version HTTP/1.0\r\nHost: 127.0.0.1\r\nAuthorization: Bearer $controllerToken\r\n\r\n".toByteArray(),
        )
        write("config/controller.port", controllerPort.toString().toByteArray())
        write("config/app.package", context.packageName.toByteArray())
        val validation =
            shell.root(
                "export TMPDIR=$BASE/tmp; $BASE/bin/mihomo -t -d $BASE/config -f $BASE/config/config.yaml >$BASE/logs/validation.log 2>&1",
                4_000,
            )
        check(validation.success) { "Mihomo config validation failed; see validation.log" }
        if (!allowed()) return
        check(command("start").success) { "Root supervisor failed to start" }
    }

    fun stop(): Boolean =
        shell
            .root(
                "if [ ! -e $BASE ]; then exit 0; fi; " +
                    "if [ ! -f $BASE/scripts/runtime.sh ] && [ ! -f $BASE/state/owned ]; then exit 0; fi; " +
                    "[ ! -L $BASE/scripts/runtime.sh ] && /system/bin/sh $BASE/scripts/runtime.sh stop",
                4_000,
            ).success

    fun delete(): Boolean {
        val retained =
            shell.root(
                "for f in core.log validation.log watchdog.log transitions.log; do echo \"[\$f]\"; tail -c 131072 $BASE/logs/\$f 2>/dev/null; done",
            )
        File(context.cacheDir, "root-tun-last-runtime.log").writeText(RootDiagnostics.redact(retained.stdout))
        return shell.root("[ ! -L $BASE ] && [ -z \"\$(find $BASE -type l -print)\" ] && rm -rf $BASE").success
    }

    fun healthy(): Boolean {
        if (!status().success) return false
        return apiHealthy()
    }

    private fun apiHealthy(): Boolean {
        if (controllerPort == 0) return false
        return runCatching {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", controllerPort), 300)
                socket.soTimeout = 300
                socket.getOutputStream().write(
                    "GET /version HTTP/1.0\r\nHost: 127.0.0.1\r\nAuthorization: Bearer $controllerToken\r\n\r\n".toByteArray(),
                )
                socket
                    .getInputStream()
                    .bufferedReader()
                    .readLine()
                    ?.contains(" 200 ") == true
            }
        }.getOrDefault(false)
    }

    fun diagnostics(): String {
        val commands =
            linkedMapOf(
                "SELinux" to "getenforce",
                "IPv4 rules" to "ip -4 rule show",
                "IPv6 rules" to "ip -6 rule show",
                "IPv4 routes" to "ip -4 route show table all",
                "IPv6 routes" to "ip -6 route show table all",
                "Links" to "ip link show",
                "Addresses" to "ip addr show",
                "iptables" to "iptables-save",
                "ip6tables" to "ip6tables-save",
                "VPN connectivity" to "dumpsys connectivity | grep -i -E 'vpn|TRANSPORT_VPN|lockdown'",
                "Root state" to "cat $BASE/state/status $BASE/state/private-dns $BASE/run/*.pid",
                "Core log" to "tail -c 262144 $BASE/logs/core.log",
                "Previous core log" to "tail -c 131072 $BASE/logs/core.log.1",
                "Validation log" to "tail -c 131072 $BASE/logs/validation.log",
                "Watchdog log" to "tail -c 131072 $BASE/logs/watchdog.log",
                "Transitions" to "tail -c 131072 $BASE/logs/transitions.log",
                "Baseline" to "cat $BASE/state/baseline.*",
            )
        val diagnosticShell = RootShell()
        return buildString {
            commands.forEach { (label, command) ->
                val result = diagnosticShell.root(command, 2_000)
                append("\n[$label] exit=${result.exitCode} timeout=${result.timedOut}\n")
                append(result.stdout)
                append(result.stderr)
            }
        }
    }

    private fun install() {
        val library = File(context.applicationInfo.nativeLibraryDir, "libroot_mihomo.so")
        check(library.isFile) { "APK has no standalone mihomo for this ABI" }
        val setup =
            shell.root(
                "umask 077; [ ! -L $BASE ] || exit 1; " +
                    "if [ -e $BASE ]; then [ -d $BASE ] && [ \"\$(stat -c %u $BASE)\" = 0 ] && " +
                    "[ -z \"\$(find $BASE -type l -print)\" ] || exit 1; fi; " +
                    "mkdir -p $BASE/bin $BASE/config/assets $BASE/scripts $BASE/state $BASE/run $BASE/logs $BASE/tmp; " +
                    "chmod 700 $BASE $BASE/bin $BASE/config $BASE/config/assets $BASE/scripts $BASE/state $BASE/run $BASE/logs $BASE/tmp",
            )
        check(setup.success) { "Unsafe or inaccessible runtime directory" }
        copyAsset(library, "$BASE/bin/mihomo.next")
        check(shell.root("chmod 700 $BASE/bin/mihomo.next && mv $BASE/bin/mihomo.next $BASE/bin/mihomo").success)
        write("scripts/runtime.sh", context.assets.open("root-tun/runtime.sh").use { it.readBytes() })
    }

    private fun stagePaths(node: MutableMap<String, Any?>) {
        var assetId = 0

        fun visit(value: Any?): Any? =
            when (value) {
                is Map<*, *> ->
                    value.entries.associate { (key, nested) ->
                        require(key is String) { "Config keys must be strings" }
                        key to
                            if (key == "path" && nested is String) {
                                val source = File(nested).let { if (it.isAbsolute) it else File(context.filesDir, nested) }
                                require(
                                    source.canonicalPath.startsWith(context.filesDir.canonicalPath + File.separator),
                                ) { "Asset path is outside app storage" }
                                require(assetId < 128) { "Too many provider assets" }
                                val destination = "$BASE/config/assets/${assetId++}"
                                if (source.exists()) copyAsset(source, destination)
                                destination
                            } else {
                                visit(nested)
                            }
                    }
                is List<*> -> value.map(::visit)
                else -> value
            }

        @Suppress("UNCHECKED_CAST")
        val staged = visit(node) as Map<String, Any?>
        node.clear()
        node.putAll(staged)
    }

    private fun copyAsset(
        source: File,
        destination: String,
    ) {
        check(source.length() <= MAX_ASSET) { "Asset exceeds 256 MiB" }
        stagedBytes += source.length()
        check(stagedBytes <= MAX_ASSET * 2) { "Assets exceed 512 MiB" }
        val digest = MessageDigest.getInstance("SHA-256")
        source.inputStream().use { stream ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        val copied =
            shell.root(
                "cp ${RootShell.quote(source.canonicalPath)} ${RootShell.quote(destination)} && " +
                    "chmod 600 ${RootShell.quote(destination)} && " +
                    "[ \"\$(sha256sum ${RootShell.quote(destination)} | cut -d' ' -f1)\" = '$hash' ]",
                3_000,
            )
        check(copied.success) { "Asset copy or digest verification failed" }
    }

    private fun write(
        relative: String,
        bytes: ByteArray,
    ) {
        check(
            shell
                .root(
                    "cat >$BASE/$relative.tmp && chmod 600 $BASE/$relative.tmp && mv $BASE/$relative.tmp $BASE/$relative",
                    2_000,
                    bytes,
                ).success,
        )
    }

    private fun command(
        operation: String,
        timeoutMs: Long = 2_000,
    ): ShellResult =
        shell.root(
            "[ ! -L $BASE/scripts/runtime.sh ] && /system/bin/sh $BASE/scripts/runtime.sh $operation",
            timeoutMs,
        )

    companion object {
        const val BASE = "/data/adb/flclash-root"
        private const val MAX_CONFIG = 8L * 1024 * 1024
        private const val MAX_ASSET = 256L * 1024 * 1024
    }
}
