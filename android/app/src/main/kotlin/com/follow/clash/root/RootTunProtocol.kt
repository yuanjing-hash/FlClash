package com.follow.clash.root

import java.util.UUID

internal enum class TunState(
    val wire: String,
) {
    DISABLED("disabled"),
    AWAITING_AUTH("awaitingAuth"),
    STARTING("starting"),
    RUNNING("running"),
    RECOVERING("recovering"),
    STOPPING("stopping"),
    FAILED("failed"),
    DEGRADED("degraded"),
    ;

    companion object {
        fun fromWire(value: String): TunState = entries.first { it.wire == value }
    }
}

internal enum class RootCode {
    ROOT_NOT_FOUND,
    ROOT_MANAGER_UNSUPPORTED,
    ANDROID_VERSION_UNSUPPORTED,
    ROOT_PERMISSION_DENIED,
    ROOT_GRANT_REQUIRED_IN_MANAGER,
    ROOT_GRANT_NOT_DETECTED,
    ROOT_PERMISSION_TIMEOUT,
    ROOT_PERMISSION_REVOKED,
    AUTOSTART_ROOT_REVOKED,
    TUN_DEVICE_UNSUPPORTED,
    TUN_CREATE_FAILED,
    NETWORK_RULES_APPLY_FAILED,
    DNS_TAKEOVER_FAILED,
    CORE_START_FAILED,
    START_TIMEOUT,
    CORE_CRASHED_RECOVERING,
    CORE_RECOVERED,
    CORE_RECOVERY_FAILED,
    CORE_CRASH_LOOP,
    LAST_SESSION_ABNORMAL_EXIT,
    MODE_SWITCHING,
    MODE_SWITCH_FAILED,
    ALWAYS_ON_VPN_CONFLICT,
    PRIVATE_DNS_AUTO_TAKEN_OVER,
    PRIVATE_DNS_STRICT,
    AUTOSTART_FAILED,
    CLEANUP_FAILED,
}

internal data class RootSnapshot(
    val schemaVersion: Int = 1,
    val epoch: String = UUID.randomUUID().toString(),
    val seq: Long = 0,
    val intentRevision: Long = 0,
    val state: TunState = TunState.DISABLED,
    val rootManager: String = "unknown",
    val authStatus: String = "unknown",
    val mode: String = "off",
    val rootTunEnabled: Boolean = false,
    val autostartEnabled: Boolean = false,
    val lastErrorCode: String? = null,
    val lastErrorAt: Long? = null,
    val warnings: List<String> = emptyList(),
    val authDeadlineAt: Long? = null,
    val startedAt: Long? = null,
    val updatedAt: Long = System.currentTimeMillis(),
    val stale: Boolean = false,
) {
    fun toMap(): Map<String, Any?> =
        linkedMapOf(
            "schemaVersion" to schemaVersion,
            "epoch" to epoch,
            "seq" to seq,
            "intentRevision" to intentRevision,
            "state" to state.wire,
            "rootManager" to rootManager,
            "authStatus" to authStatus,
            "mode" to mode,
            "rootTunEnabled" to rootTunEnabled,
            "autostartEnabled" to autostartEnabled,
            "lastErrorCode" to lastErrorCode,
            "lastErrorAt" to lastErrorAt,
            "warnings" to warnings,
            "authDeadlineAt" to authDeadlineAt,
            "startedAt" to startedAt,
            "updatedAt" to updatedAt,
            "stale" to stale,
        )
}

internal fun success(data: Any?): Map<String, Any?> = mapOf("ok" to true, "data" to data, "error" to null)

internal fun failure(
    code: RootCode,
    phase: String,
    retryable: Boolean = code !in setOf(RootCode.ROOT_NOT_FOUND, RootCode.ROOT_MANAGER_UNSUPPORTED, RootCode.ANDROID_VERSION_UNSUPPORTED),
    reason: String? = null,
): Map<String, Any?> =
    mapOf(
        "ok" to false,
        "data" to null,
        "error" to
            mapOf(
                "code" to code.name,
                "details" to
                    buildMap {
                        put("phase", phase)
                        if (reason != null) put("reason", reason)
                    },
                "retryable" to retryable,
            ),
    )

internal fun requireRequestId(value: Any?): String {
    val requestId = value as? String ?: throw IllegalArgumentException("requestId is required")
    require(
        runCatching { UUID.fromString(requestId).toString() == requestId.lowercase() }.getOrDefault(false),
    ) { "requestId must be a UUID" }
    return requestId
}
