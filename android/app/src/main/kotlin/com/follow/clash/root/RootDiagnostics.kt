package com.follow.clash.root

import android.content.Context
import android.os.Build
import com.google.gson.GsonBuilder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal object RootDiagnostics {
    fun export(
        context: Context,
        snapshot: RootSnapshot,
        logs: Map<String, Any?>,
        runtime: RootRuntime,
    ): File {
        val evidence = runtime.diagnostics(snapshot.authStatus == "granted", snapshot.rootManager)
        return archive(
            context.cacheDir,
            "${Build.MANUFACTURER} ${Build.MODEL}\n" +
                "Android ${Build.VERSION.RELEASE} SDK ${Build.VERSION.SDK_INT}\n" +
                "incremental=${Build.VERSION.INCREMENTAL}\nsecurity_patch=${Build.VERSION.SECURITY_PATCH}\n" +
                "package=${context.packageName}\n" + evidence.device,
            snapshot,
            logs,
            evidence,
        )
    }

    internal fun result(file: File): Map<String, Any> =
        mapOf("path" to file.absolutePath, "sizeBytes" to file.length(), "mimeType" to "application/zip")

    internal fun archive(
        cacheDirectory: File,
        device: String,
        snapshot: RootSnapshot,
        logs: Map<String, Any?>,
        evidence: RootDiagnosticEvidence,
    ): File {
        val directory = File(cacheDirectory, "root-tun-diagnostics").apply { check(mkdirs() || isDirectory) }
        directory.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86_400_000 }?.forEach { it.delete() }
        val file = File.createTempFile("root-tun-", ".zip", directory)
        val gson = GsonBuilder().serializeNulls().setPrettyPrinting().create()
        ZipOutputStream(file.outputStream()).use { zip ->
            fun entry(
                name: String,
                text: String,
            ) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(redact(text).toByteArray())
                zip.closeEntry()
            }
            entry("device.txt", device + "\nApp su observations:\n" + RootShell.diagnosticLog())
            entry(
                "manifest.txt",
                evidence.manifest + "\napp-su-log collected=true\nstate.json collected=true\napp-root-tun-log.json collected=true\n",
            )
            entry("state.json", gson.toJson(snapshot.toMap()))
            entry("app-root-tun-log.json", gson.toJson(logs))
            entry("network-and-core.txt", evidence.network)
            val restoreDiff = evidence.restoreDiff ?: File(cacheDirectory, "root-tun-restore-diff.txt").takeIf { it.isFile }?.readText()
            if (restoreDiff != null) entry("logs/restore-diff.txt", restoreDiff)
            val retained = File(cacheDirectory, "root-tun-last-runtime.log")
            if (retained.isFile) entry("previous-runtime.txt", retained.readText())
        }
        return file
    }

    internal fun redact(value: String): String =
        value
            .replace(Regex("(?im)(\\b(?:authorization|password|secret|token|private[-_]?key|api[-_]?key)\\s*[:=]).*$"), "$1 [redacted]")
            .replace(Regex("(?i)(bearer\\s+)[^\\s,}]+"), "$1[redacted]")
            .replace(Regex("\\b([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\\s@]+@"), "$1[redacted]@")
            .replace(Regex("(https?://[^\\s?'\\\"]+)\\?[^\\s'\\\"]+"), "$1?[redacted]")
            .replace(Regex("(?i)(?:ss|ssr|vmess|vless|trojan)://[^\\s]+"), "[redacted proxy URL]")
}

internal data class RootDiagnosticEvidence(
    val device: String,
    val network: String,
    val restoreDiff: String?,
    val manifest: String = "collector manifest unavailable",
) {
    companion object {
        private val items =
            "clock boot-state tools boot-evidence auth-data package device grep processes directories runtime-state notifications " +
                "ipv4 ipv6 iptables ip6tables nft selinux connectivity restore-diff baseline logs"

        private fun incompleteManifest(result: ShellResult): String {
            val completed =
                result.stdout
                    .lineSequence()
                    .filter { it.startsWith("[collected] ") }
                    .map { it.removePrefix("[collected] ") }
                    .associateBy { it.substringBefore(' ') }
            return "collector incomplete; exit=${result.exitCode} timeout=${result.timedOut}\n" +
                items.split(' ').joinToString("\n") { completed[it] ?: "$it not confirmed" }
        }

        fun parse(result: ShellResult): RootDiagnosticEvidence {
            fun section(name: String): String? {
                val start = "[FLCLASH:$name:BEGIN]\n"
                val end = "\n[FLCLASH:$name:END]"
                if (start !in result.stdout || end !in result.stdout) return null
                return result.stdout.substringAfter(start).substringBefore(end)
            }
            val outcome = "\ncollector exit=${result.exitCode} timeout=${result.timedOut}\n${result.stderr}"
            return RootDiagnosticEvidence(
                section("device").orEmpty() + outcome,
                (section("network") ?: result.stdout) + outcome,
                section("restore-diff"),
                section("manifest") ?: incompleteManifest(result),
            )
        }
    }
}
