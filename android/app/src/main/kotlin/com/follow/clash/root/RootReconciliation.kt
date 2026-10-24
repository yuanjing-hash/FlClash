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
        if (status != null && !status.success && runtimeState == null) return cached.copy(stale = true)
        val runtimeCode =
            status
                ?.stdout
                ?.lineSequence()
                ?.firstOrNull()
                ?.substringAfter(' ', "")
                ?.let { runCatching { RootCode.valueOf(it) }.getOrNull() }
        val reportedRevocation = status != null && "auth:revoked" in status.stdout && runtimeState == TunState.FAILED
        val auth =
            if (reportedRevocation) {
                "revoked"
            } else if (runtimeState in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING) && status?.success == true) {
                "granted"
            } else {
                root.auth
            }
        val active = setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING)
        val startIntent = cached.rootTunEnabled || runtimeState in active
        val state =
            when {
                runtimeState in setOf(TunState.FAILED, TunState.STOPPING, TunState.DISABLED) -> checkNotNull(runtimeState)
                prerequisite -> TunState.DEGRADED
                auth != "granted" && !startIntent -> TunState.DISABLED
                auth != "granted" -> TunState.AWAITING_AUTH
                runtimeState == null || (runtimeState in active && status.success != true) -> TunState.STOPPING
                else -> runtimeState
            }
        val code =
            when {
                runtimeState == TunState.FAILED -> runtimeCode?.name
                runtimeState == TunState.STOPPING ->
                    runtimeCode
                        ?.takeUnless {
                            it in setOf(RootCode.ROOT_PERMISSION_REVOKED, RootCode.AUTOSTART_ROOT_REVOKED)
                        }?.name
                prerequisite -> root.error?.name
                state == TunState.DISABLED && auth != "granted" -> null
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
            authStatus = if (status != null && "auth:revoked" in status.stdout) "revoked" else auth,
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
