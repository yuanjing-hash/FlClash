package com.follow.clash.root

import java.util.UUID

internal object RootReconciliation {
    fun initial(persisted: RootSnapshot?): RootSnapshot =
        persisted?.copy(epoch = UUID.randomUUID().toString(), seq = 0, stale = true) ?: RootSnapshot()

    fun checked(
        cached: RootSnapshot,
        root: RootStatus,
        status: ShellResult?,
    ): RootSnapshot {
        val prerequisite =
            root.error in setOf(RootCode.ROOT_NOT_FOUND, RootCode.ROOT_MANAGER_UNSUPPORTED, RootCode.ANDROID_VERSION_UNSUPPORTED)
        val runtimeState =
            status
                ?.stdout
                ?.lineSequence()
                ?.firstOrNull()
                ?.substringBefore(' ')
                ?.let { runCatching { TunState.fromWire(it) }.getOrNull() }
        val auth = if (status != null && !status.success && runtimeState == null) "notGranted" else root.auth
        val active = setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING)
        val state =
            when {
                prerequisite -> TunState.DEGRADED
                auth != "granted" -> TunState.AWAITING_AUTH
                runtimeState == null || (runtimeState in active && status.success != true) -> TunState.STOPPING
                else -> runtimeState
            }
        val code =
            when {
                prerequisite -> root.error?.name
                auth != "granted" ->
                    if (root.manager == "magisk") RootCode.ROOT_PERMISSION_DENIED.name else RootCode.ROOT_GRANT_REQUIRED_IN_MANAGER.name
                state == TunState.STOPPING -> RootCode.CLEANUP_FAILED.name
                else ->
                    status
                        ?.stdout
                        ?.lineSequence()
                        ?.firstOrNull()
                        ?.substringAfter(' ', "")
                        ?.let { runCatching { RootCode.valueOf(it).name }.getOrNull() }
            }
        return cached.copy(
            state = state,
            rootManager = root.manager,
            authStatus = auth,
            stale = false,
            mode = if (state in active) "rootTun" else cached.mode,
            rootTunEnabled = state in active || cached.rootTunEnabled,
            autostartEnabled = if (status != null) "autostart:yes" in status.stdout else cached.autostartEnabled,
            authDeadlineAt = null,
            startedAt = if (state in active) cached.startedAt else null,
            lastErrorCode = code,
            lastErrorAt = if (code != null) System.currentTimeMillis() else null,
            warnings =
                buildList {
                    if (status != null && "restore-diff:yes" in status.stdout) add(RootCode.CLEANUP_FAILED.name)
                    if (status != null && "dns:hostname" in status.stdout) add(RootCode.PRIVATE_DNS_STRICT.name)
                    if (status != null && "always-on:yes" in status.stdout) add(RootCode.ALWAYS_ON_VPN_CONFLICT.name)
                },
        )
    }
}
