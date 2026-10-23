package com.follow.clash.root

import java.io.File

internal data class RootStatus(
    val manager: String,
    val auth: String,
    val error: RootCode? = null,
)

internal class RootDetection(
    private val shell: RootShell = RootShell(),
    private val managerHint: () -> String? = { null },
) {
    fun detect(
        sdk: Int,
        previousAuth: String = "unknown",
        explicit: Boolean = false,
    ): RootStatus {
        if (sdk < 29) return RootStatus("unknown", "unknown", RootCode.ANDROID_VERSION_UNSUPPORTED)
        val version = shell.execute(listOf("su", "-v"), 500)
        val hint = managerHint()
        if (version.exitCode == 127) {
            if (hint in setOf("kernelsu", "apatch")) {
                return RootStatus(checkNotNull(hint), "notGranted", RootCode.ROOT_GRANT_REQUIRED_IN_MANAGER)
            }
            return RootStatus("none", "unknown", RootCode.ROOT_NOT_FOUND)
        }
        val text = (version.stdout + version.stderr).lowercase()
        val manager =
            when {
                "kernelsu" in text || File("/data/adb/ksu").exists() -> "kernelsu"
                "apatch" in text || File("/data/adb/ap").exists() -> "apatch"
                "magisk" in text || File("/data/adb/magisk").exists() -> "magisk"
                else -> hint ?: "unknown"
            }
        if (manager == "unknown") return RootStatus(manager, "unknown", RootCode.ROOT_MANAGER_UNSUPPORTED)
        // Magisk has no portable noninteractive grant query. Only an explicit start may prompt.
        if (manager == "magisk" && !explicit) return RootStatus(manager, previousAuth)
        val result = shell.root("id -u", if (manager == "magisk") 30_000 else 1_000)
        val auth =
            when {
                result.success && result.stdout.trim() == "0" -> "granted"
                manager != "magisk" -> "notGranted"
                result.timedOut -> "notGranted"
                else -> "denied"
            }
        val code =
            when {
                auth == "granted" -> null
                manager != "magisk" -> RootCode.ROOT_GRANT_REQUIRED_IN_MANAGER
                result.timedOut -> RootCode.ROOT_PERMISSION_TIMEOUT
                else -> RootCode.ROOT_PERMISSION_DENIED
            }
        return RootStatus(manager, auth, code)
    }

    fun cancel() = shell.cancel()
}
