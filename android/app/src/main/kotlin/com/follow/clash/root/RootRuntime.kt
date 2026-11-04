package com.follow.clash.root

import android.content.Context
import com.follow.clash.ServiceState
import com.follow.clash.core.Core
import com.follow.clash.models.SharedState
import com.follow.clash.service.models.VpnOptions
import com.google.gson.JsonParser
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.ServerSocket
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

internal class RootRuntime(
    private val context: Context,
) {
    private val shell = RootShell()
    private var phaseStartedAt = android.os.SystemClock.elapsedRealtime()
    var startPhase: String = "idle"
        private set(value) {
            val now = android.os.SystemClock.elapsedRealtime()
            RootShell.note("phase=start/$field elapsedMs=${now - phaseStartedAt}")
            phaseStartedAt = now
            field = value
        }
    private var controllerPort = 0
    private var controllerToken = ""

    @Volatile private var backend: RootCoreBackend? = null
    private var stagedBytes = 0L
    private val ownEntry =
        "[ ! -L /data/adb/service.d ] && [ ! -L $AUTOSTART ] && [ -f $AUTOSTART ] && " +
            "grep -qx '# flclash-root service.d v[12]' $AUTOSTART"
    var didInstall: Boolean = false
        private set

    fun status(): ShellResult =
        shell.root(
            "if [ ! -e $BASE ]; then echo disabled; " +
                "elif [ ! -L $BASE/scripts/runtime.sh ] && [ -f $BASE/scripts/runtime.sh ]; then " +
                "sh $BASE/scripts/runtime.sh status; " +
                "else echo 'stopping CLEANUP_FAILED'; false; fi; result=\$?; " +
                "previous_boot=\$(cat $BASE/run/boot-id 2>/dev/null || cat $BASE/state/owned.boot 2>/dev/null); " +
                "current_boot=\$(cat /proc/sys/kernel/random/boot_id); " +
                "if [ -n \"\$previous_boot\" ] && [ -n \"\$current_boot\" ] && [ \"\$previous_boot\" != \"\$current_boot\" ]; " +
                "then echo runtime-boot:previous; fi; " +
                "if $ownEntry; then echo autostart:yes; else echo autostart:no; fi; exit \$result",
        )

    fun reconcileBoot(): ShellResult = stopResult("reconcile-boot")

    fun repairSystemProxy(): ShellResult {
        val repaired = stopResult("repair-proxy")
        if (!repaired.success || repaired.stdout.lineSequence().none { it == "proxy-repair:verified" }) return repaired
        return try {
            installScripts()
            repaired
        } catch (error: Exception) {
            ShellResult(1, repaired.stdout, "Persist proxy repair script failed: ${error.message}")
        }
    }

    fun attach(
        manager: String? = null,
        authChannel: String? = null,
    ): Boolean {
        val existing = status()
        if (!existing.success || !existing.stdout.startsWith("running")) return false
        if (!loadSession()) return false
        if (!apiHealthy() && backend == null) return false
        installScripts()
        if (manager != null && authChannel != null) configureAuthorization(manager, authChannel)
        command("start").requireSuccess("Reattach root supervisor")
        if (autostartEnabled()) check(setAutostart(true))
        return true
    }

    fun start(
        sharedState: () -> SharedState,
        manager: String,
        authChannel: () -> String,
        allowed: () -> Boolean,
    ): Boolean {
        didInstall = false
        startPhase = "inspect-runtime"
        val requested = sharedState().vpnOptions
        val previous = shell.root("cat $BASE/config/vpn-options.json", 1_000)
        val applied =
            runCatching {
                com.google.gson
                    .Gson()
                    .fromJson(previous.stdout, VpnOptions::class.java)
            }.getOrNull()
        if (previous.success &&
            requested != null &&
            requested == applied &&
            installedRuntimeIsCurrent() &&
            attach(manager, authChannel())
        ) {
            startPhase = "reattach-existing-core"
            RootShell.note("Reattached existing Root Core without relaunch")
            return true
        }
        startPhase = "cleanup-previous-runtime"
        stopResult("cleanup").requireSuccess("Clean previous root runtime")
        if (!allowed()) return false
        backend?.let {
            backend = null
            Core.useBackend(null)
        }
        startPhase = "pause-embedded-core"
        if (!Core.beginRootTransition(allowed)) return false
        stagedBytes = 0
        startPhase = "install-runtime"
        install()
        didInstall = true
        startPhase = "configure-authorization"
        configureAuthorization(manager, authChannel())
        startPhase = "prepare-ui-config"
        val shared = sharedState()
        val setup =
            checkNotNull(shared.setupParams) { "UI Core setup parameters are unavailable" }.let { params ->
                params.copy(selectedMap = params.selectedMap + currentSelections())
            }
        check(File(context.filesDir, "config.yaml").isFile) { "Active UI config.yaml is missing" }
        val gson = com.google.gson.Gson()
        val appUid = context.applicationInfo.uid
        val packages = context.packageManager.getInstalledApplications(0).associate { it.uid.toString() to it.packageName }
        val systemDns = RootLaunchConfig.systemDns(context)
        Core.updateDnsCapture(systemDns.joinToString(","))
        val prepared =
            RootLaunchConfig.prepare(
                shared.copy(setupParams = setup),
                appUid,
                { name ->
                    runCatching { context.packageManager.getApplicationInfo(name, 0).uid }.getOrNull()
                },
                packages,
                systemDns,
            )
        controllerPort = ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1")).use { it.localPort }
        controllerToken = UUID.randomUUID().toString() + UUID.randomUUID().toString()
        val launch =
            mapOf(
                "init" to mapOf("home-dir" to context.filesDir.path, "version" to android.os.Build.VERSION.SDK_INT),
                "updates" to (shared.updateParams ?: JsonParser.parseString(Core.currentUpdates())),
                "port" to controllerPort,
                "token" to controllerToken,
                "appUid" to appUid,
                "ready" to "$BASE/run/core-ready",
            ) + prepared.launch
        val session = File(context.filesDir, "root-core-session.json")
        session.writeText(gson.toJson(mapOf("port" to controllerPort, "token" to controllerToken)))
        writeAll(
            prepared.files.mapKeys { (name, _) -> "config/$name" }.mapValues { (_, value) -> value.toByteArray() } +
                mapOf(
                    "config/root-core.json" to gson.toJson(launch).toByteArray(),
                    "config/config.yaml" to "# FlClash shared Core reads the active UI profile from app storage.\n".toByteArray(),
                    "config/app.package" to context.packageName.toByteArray(),
                ),
        )
        startPhase = "validate-ui-config"
        val validation =
            shell.root(
                "export TMPDIR=$BASE/tmp; exec $BASE/bin/mihomo --check --root-config $BASE/config/root-core.json >$BASE/logs/validation.log 2>&1",
                15_000,
            )
        if (!validation.success) {
            val evidence = shell.root("tail -c 8192 $BASE/logs/validation.log", 1_000)
            validation.copy(stdout = evidence.stdout).requireSuccess("FlClash UI config validation")
        }
        if (!allowed()) return false
        startPhase = "launch-supervisor"
        write("config/root-tun-enabled", "1\n".toByteArray())
        command("settings").requireSuccess("Persist root settings")
        command("start").requireSuccess("Start root supervisor")
        startPhase = "await-core"
        return true
    }

    fun stop(): Boolean {
        val stopped = stopResult().success
        return stopped && detachCore(wait = true)
    }

    fun detachCore(wait: Boolean = false): Boolean {
        backend = null
        val shared = ServiceState.currentSharedState
        val updates = shared.updateParams ?: JsonParser.parseString(Core.currentUpdates())
        val selections = currentSelections()
        Core.useBackend(null)
        val gson = com.google.gson.Gson()
        val init = mapOf("home-dir" to context.filesDir.path, "version" to android.os.Build.VERSION.SDK_INT, "preserve-responses" to true)
        val setup = shared.setupParams?.let { it.copy(selectedMap = it.selectedMap + selections) }
        val restoring =
            Core.restoreEmbedded(
                listOf(
                    gson.toJson(mapOf("method" to "initClash", "arguments" to init)),
                    gson.toJson(mapOf("method" to "setupConfig", "arguments" to setup)),
                    gson.toJson(mapOf("method" to "updateConfig", "arguments" to updates)),
                ),
            )
        return !wait || runCatching { restoring.get(15, TimeUnit.SECONDS) }.getOrDefault(false)
    }

    fun dnsProbe(): RootHealth.DnsProbe = if (backend?.dnsEnabled() == true) RootHealth.dns() else RootHealth.DnsProbe("ok", "ok")

    val startupError: String? get() = backend?.startupError

    private fun currentSelections(): Map<String, String> =
        JsonParser
            .parseString(Core.currentSelections())
            .asJsonObject
            .entrySet()
            .associate { (key, value) -> key to value.asString }

    private fun loadSession(): Boolean =
        runCatching {
            val session = JsonParser.parseString(File(context.filesDir, "root-core-session.json").readText()).asJsonObject
            controllerPort = session["port"].asInt
            controllerToken = session["token"].asString
            true
        }.getOrDefault(false)

    fun attachCore(): Boolean {
        if (com.follow.clash.BuildConfig.ROOT_TUN_SAFE_MODE) return false
        if (!loadSession()) return false
        return apiHealthy()
    }

    private fun stopResult(operation: String = "stop"): ShellResult =
        try {
            val script = File.createTempFile("root-tun-cleanup-", ".sh", context.cacheDir)
            try {
                context.assets.open("root-tun/runtime.sh").use { input -> script.outputStream().use { input.copyTo(it) } }
                shell.root(
                    "if [ ! -e $BASE ] && [ ! -L $BASE ]; then exit 0; fi; " +
                        "ROOT_PROXY_CLASSPATH=${RootShell.quote(context.applicationInfo.sourceDir)} " +
                        "exec sh ${RootShell.quote(script.path)} $operation",
                    15_000,
                )
            } finally {
                script.delete()
            }
        } catch (error: IOException) {
            ShellResult(1, "", "Stage cleanup script failed: ${error.message}")
        }

    fun delete(): Boolean {
        if (!stopResult("cleanup").success) return false
        val retained =
            shell.root(
                "for f in core.log validation.log launch.log watchdog.log transitions.log boot.log; do echo \"[\$f]\"; tail -c 131072 $BASE/logs/\$f 2>/dev/null; done",
            )
        File(context.cacheDir, "root-tun-last-runtime.log").writeText(RootDiagnostics.redact(retained.stdout))
        val retainedDiff = File.createTempFile("root-tun-restore-", ".txt", context.cacheDir)
        try {
            val copied =
                shell.root(
                    "if [ -f $BASE/logs/restore-diff.txt ]; then cat $BASE/logs/restore-diff.txt >${RootShell.quote(
                        retainedDiff.path,
                    )}; fi",
                )
            if (!copied.success || !retainedDiff.renameTo(File(context.cacheDir, "root-tun-restore-diff.txt"))) return false
        } finally {
            retainedDiff.delete()
        }
        return shell.root("[ ! -L $BASE ] && [ -z \"\$(find $BASE -type l -print)\" ] && rm -rf $BASE").success
    }

    fun autostartEnabled(): Boolean {
        val result = shell.root("if $ownEntry; then echo yes; else echo no; fi")
        check(result.success) { "Autostart state is unavailable" }
        return result.stdout.trim() == "yes"
    }

    fun setAutostart(enabled: Boolean): Boolean {
        val result =
            if (enabled) {
                val entry = context.assets.open("root-tun/service.d.sh").use { it.readBytes() }
                shell.root(
                    "umask 077; [ ! -L /data/adb/service.d ] && [ ! -L $AUTOSTART ] && " +
                        "{ [ ! -e $AUTOSTART ] || { $ownEntry; }; } && [ ! -L $BASE ] && [ -d $BASE/config ] && " +
                        "[ -z \"\$(find $BASE -type l -print)\" ] && " +
                        "[ -s $BASE/config/root-core.json ] && [ -f $BASE/bin/proxy-helper.jar ] && [ -f $BASE/scripts/runtime.sh ] && " +
                        "[ \"\$(cat $BASE/config/root-tun-enabled)\" = 1 ] && " +
                        "mkdir -p /data/adb/service.d && cat >$BASE/tmp/autostart-entry && " +
                        "chmod 700 $BASE/tmp/autostart-entry && chown 0:0 $BASE/tmp/autostart-entry && " +
                        "echo 1 >$BASE/config/autostart-enabled.tmp && chmod 600 $BASE/config/autostart-enabled.tmp && " +
                        "mv $BASE/config/autostart-enabled.tmp $BASE/config/autostart-enabled && " +
                        "mv $BASE/tmp/autostart-entry $AUTOSTART && sh $BASE/scripts/runtime.sh settings",
                    2_300,
                    entry,
                )
            } else {
                shell.root(
                    "if $ownEntry; then rm -f $AUTOSTART || exit 1; fi; " +
                        "if [ -d $BASE/config ]; then [ ! -L $BASE ] && " +
                        "[ -z \"\$(find $BASE -type l -print)\" ] && " +
                        "echo 0 >$BASE/config/autostart-enabled.tmp && chmod 600 $BASE/config/autostart-enabled.tmp && " +
                        "mv $BASE/config/autostart-enabled.tmp $BASE/config/autostart-enabled && " +
                        "sh $BASE/scripts/runtime.sh settings; fi",
                    2_300,
                )
            }
        return result.success
    }

    fun healthy(status: ShellResult = status()): Boolean {
        if (!readyForDns(status)) return false
        return apiHealthy()
    }

    @Synchronized
    private fun apiHealthy(): Boolean {
        if (controllerPort == 0) return false
        backend?.let { return it.healthy() }
        val candidate = RootCoreBackend(controllerPort, controllerToken)
        return try {
            candidate.connect()
            if (!candidate.healthy()) {
                candidate.close()
                false
            } else {
                startPhase = "handoff-ui-config"
                Core.useBackend(candidate)
                backend = candidate
                candidate.healthy()
            }
        } catch (_: Exception) {
            candidate.close()
            false
        }
    }

    fun diagnostics(
        privileged: Boolean,
        manager: String,
    ): RootDiagnosticEvidence {
        val authorization =
            context.assets
                .open("root-tun/authorization.sh")
                .bufferedReader()
                .use { it.readText() }
        val collector =
            context.assets
                .open("root-tun/diagnostics.sh")
                .bufferedReader()
                .use { it.readText() }
        val otaCollector =
            context.assets
                .open("root-tun/ota-diagnostics.sh")
                .bufferedReader()
                .use { it.readText() }
        val script =
            (
                "AUTH_SOURCE=${RootShell.quote(authorization)}\n" +
                    "OTA_SOURCE=${RootShell.quote(otaCollector)}\n" +
                    "export APP_UID=${context.applicationInfo.uid} ROOT_MANAGER=${RootShell.quote(manager)}\n" + collector
            ).toByteArray()
        val diagnosticShell = RootShell(4 * 1024 * 1024)
        val result =
            if (privileged) {
                diagnosticShell.root("sh", 18_000, script)
            } else {
                diagnosticShell.execute(listOf("sh", "-c", "export TMPDIR=${RootShell.quote(context.cacheDir.path)}; sh"), 18_000, script)
            }
        return RootDiagnosticEvidence.parse(result)
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
        setup.requireSuccess("Create root runtime directories")
        val identity = runtimeIdentity(library)
        val cached =
            shell.root(
                "${runtimeIdentityCheck(identity)} && " +
                    "[ -x $BASE/bin/mihomo ] && [ -f $BASE/bin/proxy-helper.jar ] && " +
                    "sha256sum -c $BASE/config/runtime.sha256 >/dev/null",
            )
        if (cached.success) return
        copyAsset(library, "$BASE/bin/mihomo.next")
        shell
            .root("chmod 700 $BASE/bin/mihomo.next && mv $BASE/bin/mihomo.next $BASE/bin/mihomo")
            .requireSuccess("Install executable mihomo")
        installProxyHelper()
        installScripts()
        shell
            .root(
                "sha256sum $BASE/bin/mihomo $BASE/bin/proxy-helper.jar >$BASE/config/runtime.sha256",
            ).requireSuccess("Record runtime integrity")
        write("config/runtime.apk", identity.toByteArray())
    }

    private fun runtimeIdentity(library: File): String =
        "${context.packageName}:${context.packageManager.getPackageInfo(
            context.packageName,
            0,
        ).lastUpdateTime}:${library.length()}"

    private fun runtimeIdentityCheck(identity: String): String =
        "[ \"\$(cat $BASE/config/runtime.apk 2>/dev/null)\" = ${RootShell.quote(identity)} ]"

    private fun installedRuntimeIsCurrent(): Boolean {
        val library = File(context.applicationInfo.nativeLibraryDir, "libroot_mihomo.so")
        return library.isFile && shell.root(runtimeIdentityCheck(runtimeIdentity(library)), 1_000).success
    }

    private fun installProxyHelper() {
        val staged = File.createTempFile("root-helper-", ".jar", context.cacheDir)
        try {
            var count = 0
            var size = 0L
            ZipOutputStream(staged.outputStream()).use { output ->
                output.setLevel(0)
                ZipFile(context.applicationInfo.sourceDir).use { apk ->
                    for (entry in apk.entries()) {
                        if (!entry.name.matches(Regex("classes\\d*\\.dex"))) continue
                        size += entry.size
                        check(entry.size > 0 && size <= MAX_ASSET) { "APK DEX exceeds size limit" }
                        output.putNextEntry(ZipEntry(entry.name))
                        apk.getInputStream(entry).use { it.copyTo(output) }
                        output.closeEntry()
                        count++
                    }
                }
            }
            check(count > 0) { "APK has no Root helper" }
            copyAsset(staged, "$BASE/bin/proxy-helper.jar")
            shell.root("chmod 400 $BASE/bin/proxy-helper.jar").requireSuccess("Protect Root helper")
        } finally {
            staged.delete()
        }
    }

    private fun installScripts() {
        writeAll(
            listOf("authorization.sh", "runtime.sh").associate { name ->
                "scripts/$name" to context.assets.open("root-tun/$name").use { it.readBytes() }
            },
        )
    }

    private fun configureAuthorization(
        manager: String,
        authChannel: String,
    ) {
        writeAll(
            mapOf(
                "config/app.uid" to "${context.applicationInfo.uid}\n".toByteArray(),
                "config/root.manager" to "$manager\n".toByteArray(),
                "config/app-auth" to authChannel.toByteArray(),
            ),
        )
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
        copied.requireSuccess("Copy and verify ${source.name}")
    }

    private fun write(
        relative: String,
        bytes: ByteArray,
    ) {
        shell
            .root(
                "cat >$BASE/$relative.tmp && chmod 600 $BASE/$relative.tmp && mv $BASE/$relative.tmp $BASE/$relative",
                2_000,
                bytes,
            ).requireSuccess("Write $relative")
    }

    private fun writeAll(files: Map<String, ByteArray>) {
        val (script, input) = batchPublication(BASE, files)
        shell.root(script, 4_000, input).requireSuccess("Publish runtime settings")
    }

    private fun command(
        operation: String,
        timeoutMs: Long = 2_000,
    ): ShellResult =
        shell.root(
            "[ ! -L $BASE/scripts/runtime.sh ] && sh $BASE/scripts/runtime.sh $operation",
            timeoutMs,
        )

    companion object {
        const val BASE = "/data/adb/flclash-root"
        private const val AUTOSTART = "/data/adb/service.d/flclash-root.sh"
        private const val MAX_CONFIG = 8L * 1024 * 1024
        private const val MAX_ASSET = 256L * 1024 * 1024

        internal fun batchPublication(
            base: String,
            files: Map<String, ByteArray>,
        ): Pair<String, ByteArray> {
            val input = ByteArrayOutputStream()
            files.values.forEach(input::write)
            val script = StringBuilder("set -e; umask 077; ")
            script.append("publication_input=\$(mktemp ${RootShell.quote("$base/.publication.XXXXXX")}); ")
            val cleanup =
                "publication_status=\$?; if [ \"\$publication_status\" -ne 0 ]; then " +
                    "printf 'root-publication: file=%s exit=%s\\n' \"\$publication_step\" \"\$publication_status\" >&2; fi; " +
                    "rm -f \"\$publication_input\""
            script.append("publication_step=input; trap ${RootShell.quote(cleanup)} EXIT; ")
            script.append("cat >\"\$publication_input\"; publication_size=\$(wc -c <\"\$publication_input\"); ")
            script.append(
                "[ \"\$publication_size\" -eq ${input.size()} ] || { " +
                    "printf 'root-publication: expected=%s actual=%s\\n' ${input.size()} \"\$publication_size\" >&2; exit 1; }; ",
            )
            var offset = 0
            for ((name, bytes) in files) {
                require(name.matches(Regex("[A-Za-z0-9_./-]+")) && !name.contains(".."))
                val path = RootShell.quote("$base/$name")
                val temporary = RootShell.quote("$base/$name.tmp")
                script.append("publication_step=${RootShell.quote(name)}; ")
                if (bytes.isEmpty()) {
                    script.append(": >$temporary; ")
                } else {
                    script.append("tail -c +${offset + 1} \"\$publication_input\" | head -c ${bytes.size} >$temporary; ")
                }
                script.append("[ \"\$(wc -c <$temporary)\" -eq ${bytes.size} ]; ")
                script.append("chmod 600 $temporary; mv $temporary $path; ")
                offset += bytes.size
            }
            return script.toString() to input.toByteArray()
        }

        internal fun readyForDns(status: ShellResult): Boolean =
            status.success &&
                status.stdout
                    .lineSequence()
                    .firstOrNull()
                    ?.substringBefore(' ') == "running"

        internal fun dnsProbePolicy(existing: Map<*, *>?): Map<*, *> =
            mapOf(RootHealth.PROBE_DOMAIN to "rcode://success") + existing.orEmpty().filterKeys { it != RootHealth.PROBE_DOMAIN }

        private val GEO_ASSETS =
            linkedMapOf(
                "geoip.metadb" to listOf("GEOIP.metadb", "Country.mmdb", "geoip.db"),
                "GeoIP.dat" to listOf("GEOIP.dat"),
                "GeoSite.dat" to listOf("GEOSITE.dat"),
                "ASN.mmdb" to listOf("ASN.mmdb"),
            )

        internal fun geoAssets(directory: File): Map<String, File> {
            val files =
                directory
                    .listFiles()
                    .orEmpty()
                    .filter { it.isFile && it.length() > 0 }
                    .sortedBy { it.name }
            return GEO_ASSETS
                .mapNotNull { (target, aliases) ->
                    aliases
                        .firstNotNullOfOrNull { alias -> files.firstOrNull { it.name.equals(alias, ignoreCase = true) } }
                        ?.let { target to it }
                }.toMap()
        }

        internal fun publishGeoAsset(
            directory: String,
            target: String,
        ): String {
            val aliases = GEO_ASSETS.getValue(target).joinToString(" -o ") { "-iname ${RootShell.quote(it)}" }
            return "mv ${RootShell.quote("$directory/$target.next")} ${RootShell.quote("$directory/$target")} && " +
                "find ${RootShell.quote(directory)} -maxdepth 1 -type f \\( $aliases \\) " +
                "! -name ${RootShell.quote(target)} -exec rm -f {} \\;"
        }
    }
}
