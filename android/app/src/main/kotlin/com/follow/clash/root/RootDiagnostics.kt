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
        val directory = File(context.cacheDir, "root-tun-diagnostics").apply { mkdirs() }
        directory.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86_400_000 }?.forEach { it.delete() }
        val file = File(directory, "root-tun-${System.currentTimeMillis()}.zip")
        val gson = GsonBuilder().serializeNulls().setPrettyPrinting().create()
        val network =
            if (snapshot.authStatus == "granted") {
                runtime.diagnostics()
            } else {
                val result = RootShell().execute(listOf("sh", "-c", "getenforce; ip rule; ip -6 rule; ip link; ip addr"))
                "Root access unavailable; grant access in the manager and recheck to collect privileged evidence.\n${result.stdout}\n${result.stderr}"
            }
        ZipOutputStream(file.outputStream()).use { zip ->
            fun entry(
                name: String,
                text: String,
            ) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(redact(text).toByteArray())
                zip.closeEntry()
            }
            entry(
                "device.txt",
                "${Build.MANUFACTURER} ${Build.MODEL}\nAndroid ${Build.VERSION.RELEASE} API ${Build.VERSION.SDK_INT}\npackage=${context.packageName}\n",
            )
            entry("state.json", gson.toJson(snapshot.toMap()))
            entry("app-root-tun-log.json", gson.toJson(logs))
            entry("network-and-core.txt", network)
            val retained = File(context.cacheDir, "root-tun-last-runtime.log")
            if (retained.isFile) entry("previous-runtime.txt", retained.readText())
        }
        return file
    }

    internal fun redact(value: String): String =
        value
            .replace(Regex("(?im)(\\b(?:authorization|password|secret|token|private[-_]?key|api[-_]?key)\\s*[:=]).*$"), "$1 [redacted]")
            .replace(Regex("(?i)(bearer\\s+)[^\\s,}]+"), "$1[redacted]")
            .replace(Regex("([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\\s@]+@"), "$1[redacted]@")
            .replace(Regex("(https?://[^\\s?'\\\"]+)\\?[^\\s'\\\"]+"), "$1?[redacted]")
            .replace(Regex("(?i)(?:ss|ssr|vmess|vless|trojan)://[^\\s]+"), "[redacted proxy URL]")
}
