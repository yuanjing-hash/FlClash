package com.follow.clash.root

import java.io.File

internal class RootPreviousSession(
    private val marker: File,
) {
    private var previous = runCatching { marker.readText().trim() }.getOrNull()
    private var checked = false

    fun clear() {
        previous = null
        checked = true
        marker.delete()
    }

    fun observe(
        raw: String,
        snapshot: RootSnapshot,
    ): Boolean {
        if (snapshot.stale) return false
        val session =
            raw
                .lineSequence()
                .singleOrNull { it.startsWith("session:") }
                ?.removePrefix("session:")
                ?.takeIf { it.isNotBlank() }
                ?: return false
        val stop = raw.lineSequence().singleOrNull { it.startsWith("stop:") }?.removePrefix("stop:") ?: return false
        if (stop !in setOf("active", "normal", "abnormal") || snapshot.state == TunState.STOPPING) return false
        val abnormal = !checked && previous == session && stop != "normal"
        checked = true
        runCatching {
            if (snapshot.state in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING)) {
                marker.writeText(session)
            } else {
                marker.delete()
            }
        }
        return abnormal
    }
}
