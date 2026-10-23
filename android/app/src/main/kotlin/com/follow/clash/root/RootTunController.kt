package com.follow.clash.root

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.AtomicFile
import com.follow.clash.BuildConfig
import com.google.gson.GsonBuilder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

internal class RootTunController(
    private val context: Context,
    private val stopVpn: suspend () -> Boolean,
    private val selections: () -> Map<String, String>,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val operations = Mutex()
    private val detection = RootDetection(managerHint = ::installedManager)
    private val runtime = RootRuntime(context)
    private val main = Handler(Looper.getMainLooper())
    private val gson = GsonBuilder().serializeNulls().create()
    private val stateFile = AtomicFile(File(context.filesDir, "root-tun-state.json"))
    private val history = ArrayDeque<Map<String, Any?>>()
    private val requests = linkedMapOf<String, Pair<String, Map<String, Any?>>>()
    private val logs = ArrayDeque<Map<String, Any?>>()
    private var listener: ((Map<String, Any?>) -> Unit)? = null

    @Volatile private var desiredRunning = false
    private var monitorStarted = false
    private var lastRuntimeEvent = ""
    private var lastPrivateDnsMode: String? = null

    @Volatile
    var snapshot: RootSnapshot =
        runCatching {
            stateFile
                .openRead()
                .use { gson.fromJson(it.reader(), RootSnapshot::class.java) }
                .copy(epoch = UUID.randomUUID().toString(), seq = 0, stale = true)
        }.getOrDefault(RootSnapshot(stale = true))
        private set

    private var runtimeMayExist = snapshot.rootTunEnabled && snapshot.stale

    val selected: Boolean get() = snapshot.mode == "rootTun"
    val runningRequested: Boolean get() = desiredRunning

    @Synchronized
    fun subscribe(
        epoch: String?,
        afterSeq: Long,
        sink: (Map<String, Any?>) -> Unit,
    ) {
        listener = sink
        val pending = history.filter { (it["seq"] as Long) > afterSeq }
        if (epoch == snapshot.epoch && afterSeq <= snapshot.seq &&
            (afterSeq == snapshot.seq || pending.firstOrNull()?.get("seq") == afterSeq + 1)
        ) {
            pending.forEach { event -> deliver(sink, event) }
        } else {
            publish(snapshot)
        }
    }

    private fun deliver(
        sink: (Map<String, Any?>) -> Unit,
        event: Map<String, Any?>,
    ) {
        main.post {
            if (synchronized(this) { listener === sink }) sink(event)
        }
    }

    @Synchronized
    fun unsubscribe() {
        listener = null
    }

    suspend fun detect(): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            if (BuildConfig.ROOT_TUN_SAFE_MODE) return@withContext success(snapshot.toMap())
            val root = RootDetection(managerHint = ::installedManager).detect(Build.VERSION.SDK_INT, snapshot.authStatus)
            synchronized(this@RootTunController) {
                val nextState =
                    when {
                        root.error in PREREQUISITES &&
                            snapshot.state !in
                            setOf(
                                TunState.STARTING,
                                TunState.RUNNING,
                                TunState.RECOVERING,
                                TunState.STOPPING,
                            )
                        -> TunState.DEGRADED
                        snapshot.state == TunState.DEGRADED -> TunState.DISABLED
                        else -> snapshot.state
                    }
                publish(snapshot.copy(rootManager = root.manager, authStatus = root.auth, state = nextState), root.error)
                success(snapshot.toMap())
            }
        }

    @Synchronized
    fun command(
        method: String,
        arguments: Map<*, *>,
    ): Map<String, Any?> {
        val requestId = arguments["requestId"] as? String ?: throw IllegalArgumentException("requestId is required")
        require(
            runCatching { UUID.fromString(requestId).toString() == requestId.lowercase() }.getOrDefault(false),
        ) { "requestId must be a UUID" }
        val reason = if (method == "stop") arguments["reason"] as? String else null
        val fingerprint = "$method:$reason"
        requests[requestId]?.let { (previous, result) ->
            require(previous == fingerprint) { "requestId was reused with different parameters" }
            return result
        }
        if (method == "stop") {
            require(reason in STOP_REASONS) { "Invalid stop reason" }
            require(reason != "cancelAuth" || snapshot.state == TunState.AWAITING_AUTH) { "cancelAuth requires awaitingAuth" }
            require(reason != "acknowledgeFailure" || snapshot.state == TunState.FAILED) { "acknowledgeFailure requires failed" }
        }
        check(!BuildConfig.ROOT_TUN_SAFE_MODE) { "Root TUN is disabled in safe mode" }
        if (method in setOf("start", "requestAuth") && snapshot.state == TunState.DEGRADED) {
            val code = snapshot.lastErrorCode?.let { runCatching { RootCode.valueOf(it) }.getOrNull() }
            if (code in PREREQUISITES) return remember(requestId, fingerprint, failure(checkNotNull(code), "detectRoot"))
        }
        val revision = snapshot.intentRevision + 1
        val coalesced =
            method in setOf("start", "requestAuth") && desiredRunning && !snapshot.stale &&
                snapshot.state in setOf(TunState.RUNNING, TunState.STARTING, TunState.AWAITING_AUTH, TunState.RECOVERING)
        if (!coalesced) {
            when (method) {
                "start", "requestAuth" -> {
                    desiredRunning = true
                    publish(
                        snapshot.copy(
                            intentRevision = revision,
                            mode = "rootTun",
                            rootTunEnabled = true,
                            lastErrorCode = null,
                            lastErrorAt = null,
                        ),
                    )
                }
                "stop", "cleanupResidue" -> {
                    desiredRunning = false
                    detection.cancel()
                    publish(snapshot.copy(intentRevision = revision, state = TunState.STOPPING, authDeadlineAt = null))
                }
                "recheckRoot" -> publish(snapshot.copy(intentRevision = revision))
                else -> throw IllegalArgumentException("Unknown command")
            }
            scope.launch {
                operations.withLock {
                    if (!current(revision)) return@withLock
                    try {
                        when (method) {
                            "start", "requestAuth" -> authorizeAndStart(revision, requestId)
                            "recheckRoot" -> recheck(revision, requestId)
                            else -> stop(revision, requestId, reason ?: "disable", method == "cleanupResidue")
                        }
                    } catch (_: Exception) {
                        if (current(revision)) {
                            if (runtime.stop()) {
                                report(
                                    revision,
                                    snapshot.copy(state = TunState.FAILED, stale = false),
                                    RootCode.CORE_START_FAILED,
                                    requestId,
                                )
                            } else {
                                report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED, requestId)
                            }
                        }
                    }
                }
            }
        }
        val result =
            success(
                mapOf(
                    "requestId" to requestId,
                    "intentRevision" to snapshot.intentRevision,
                    "disposition" to if (coalesced) "coalesced" else "accepted",
                    "snapshot" to snapshot.toMap(),
                ),
            )
        return remember(requestId, fingerprint, result)
    }

    private fun remember(
        requestId: String,
        fingerprint: String,
        result: Map<String, Any?>,
    ): Map<String, Any?> {
        requests[requestId] = fingerprint to result
        if (requests.size > 256) requests.remove(requests.keys.first())
        return result
    }

    private suspend fun authorizeAndStart(
        revision: Long,
        requestId: String,
    ) {
        val detected = detection.detect(Build.VERSION.SDK_INT, snapshot.authStatus)
        if (!current(revision)) return
        if (detected.error in PREREQUISITES) {
            report(
                revision,
                snapshot.copy(state = TunState.DEGRADED, rootManager = detected.manager, authStatus = detected.auth),
                detected.error,
                requestId,
            )
            return
        }
        report(
            revision,
            snapshot.copy(
                state = TunState.AWAITING_AUTH,
                rootManager = detected.manager,
                authStatus = "notGranted",
                authDeadlineAt = if (detected.manager == "magisk") System.currentTimeMillis() + 30_000 else null,
            ),
            requestId = requestId,
        )
        val root = detection.detect(Build.VERSION.SDK_INT, explicit = true)
        if (!current(revision)) return
        if (root.auth != "granted") {
            report(
                revision,
                snapshot.copy(
                    authStatus = root.auth,
                    state = if (root.manager == "magisk") TunState.FAILED else TunState.AWAITING_AUTH,
                    authDeadlineAt = null,
                ),
                root.error,
                requestId,
            )
            return
        }
        report(revision, snapshot.copy(authStatus = "granted", authDeadlineAt = null), requestId = requestId)
        start(revision, requestId)
    }

    private suspend fun recheck(
        revision: Long,
        requestId: String,
    ) {
        val root = detection.detect(Build.VERSION.SDK_INT, snapshot.authStatus)
        if (!current(revision)) return
        if (snapshot.stale && root.auth == "granted") {
            val attached = runtime.attach()
            if (!current(revision)) return
            if (attached) {
                synchronized(this) {
                    if (!current(revision)) return
                    desiredRunning = true
                    runtimeMayExist = true
                    report(
                        revision,
                        snapshot.copy(
                            state = TunState.RUNNING,
                            mode = "rootTun",
                            rootTunEnabled = true,
                            authStatus = root.auth,
                            rootManager = root.manager,
                            stale = false,
                        ),
                        RootCode.LAST_SESSION_ABNORMAL_EXIT,
                        requestId,
                    )
                }
                RootTunService.start(context)
                startMonitor()
                return
            }
            val status = runtime.status()
            if (!current(revision)) return
            if (status.stdout.isBlank()) {
                report(
                    revision,
                    snapshot.copy(
                        state = TunState.DISABLED,
                        startedAt = null,
                        rootManager = root.manager,
                        authStatus = root.auth,
                        stale = false,
                    ),
                    RootCode.LAST_SESSION_ABNORMAL_EXIT,
                    requestId,
                )
                return
            }
            runtimeMayExist = true
            acceptStatus(status.stdout, requestId, revision)
        }
        if (root.error in PREREQUISITES) {
            report(
                revision,
                snapshot.copy(state = TunState.DEGRADED, rootManager = root.manager, authStatus = root.auth),
                root.error,
                requestId,
            )
        } else if (root.auth == "granted" && desiredRunning) {
            report(revision, snapshot.copy(rootManager = root.manager, authStatus = root.auth), requestId = requestId)
            if (snapshot.state != TunState.RUNNING || snapshot.stale) start(revision, requestId)
        } else {
            val state = if (snapshot.state == TunState.DEGRADED) TunState.DISABLED else snapshot.state
            report(
                revision,
                snapshot.copy(state = state, rootManager = root.manager, authStatus = root.auth),
                if (state == TunState.AWAITING_AUTH) RootCode.ROOT_GRANT_NOT_DETECTED else null,
                requestId,
            )
        }
    }

    private suspend fun start(
        revision: Long,
        requestId: String,
    ) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        report(
            revision,
            snapshot.copy(state = TunState.STARTING, stale = false, lastErrorCode = null, lastErrorAt = null),
            RootCode.MODE_SWITCHING,
            requestId,
        )
        if (!stopVpn()) {
            report(revision, snapshot.copy(state = TunState.FAILED), RootCode.MODE_SWITCH_FAILED, requestId)
            return
        }
        if (!current(revision)) return
        runtimeMayExist = true
        runtime.start(selections()) { current(revision) && SystemClock.elapsedRealtime() < deadline }
        if (runtime.didInstall && current(revision)) {
            synchronized(this) {
                history.clear()
                snapshot = snapshot.copy(epoch = UUID.randomUUID().toString(), seq = 0)
                report(revision, snapshot)
            }
        }
        if (!current(revision)) {
            runtime.stop()
            return
        }
        RootTunService.start(context)
        startMonitor()
        while (current(revision) && SystemClock.elapsedRealtime() < deadline) {
            val status = runtime.status()
            if (status.stdout.startsWith("failed") || status.stdout.contains("CLEANUP_FAILED")) {
                acceptStatus(status.stdout, requestId, revision)
                return
            }
            if (runtime.healthy()) {
                if (!RootHealth.dns()) {
                    val cleaned = runtime.stop()
                    if (current(revision)) {
                        report(
                            revision,
                            snapshot.copy(state = if (cleaned) TunState.FAILED else TunState.STOPPING),
                            if (cleaned) RootCode.DNS_TAKEOVER_FAILED else RootCode.CLEANUP_FAILED,
                            requestId,
                        )
                    }
                    return
                }
                report(revision, snapshot.copy(state = TunState.RUNNING, startedAt = System.currentTimeMillis()), requestId = requestId)
                startMonitor()
                return
            }
            delay(200)
        }
        val stopped = runtime.stop()
        if (current(revision)) {
            report(
                revision,
                snapshot.copy(state = if (stopped) TunState.FAILED else TunState.STOPPING),
                if (stopped) RootCode.START_TIMEOUT else RootCode.CLEANUP_FAILED,
                requestId,
            )
        }
    }

    private fun stop(
        revision: Long,
        requestId: String,
        reason: String,
        force: Boolean,
    ) {
        val noRuntime = !force && !runtimeMayExist
        val clean = noRuntime || runtime.stop()
        if (!current(revision)) return
        if (!clean) {
            report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED, requestId)
            return
        }
        val disable = reason in setOf("disable", "switchToVpn", "cancelAuth")
        if (disable && !noRuntime && !runtime.delete()) {
            report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED, requestId)
            return
        }
        if (disable) runtimeMayExist = false
        report(
            revision,
            snapshot.copy(
                state = TunState.DISABLED,
                stale = false,
                startedAt = null,
                rootTunEnabled = if (disable) false else snapshot.rootTunEnabled,
                mode =
                    if (reason == "switchToVpn") {
                        "vpn"
                    } else if (disable) {
                        "off"
                    } else {
                        snapshot.mode
                    },
                autostartEnabled = false,
                lastErrorCode = null,
                lastErrorAt = null,
            ),
            requestId = requestId,
        )
        RootTunService.stop(context)
    }

    @Synchronized
    private fun startMonitor() {
        if (monitorStarted) return
        monitorStarted = true
        scope.launch {
            try {
                while (true) {
                    delay(1_000)
                    operations.withLock {
                        if (!selected || (!desiredRunning && snapshot.state != TunState.STOPPING)) return@withLock
                        val revision = snapshot.intentRevision
                        val status = runtime.status()
                        if (!current(revision)) return@withLock
                        acceptStatus(status.stdout, revision = revision)
                        if (!status.success && status.stdout.isBlank()) {
                            if (runtime.stop()) {
                                report(revision, snapshot.copy(state = TunState.FAILED), RootCode.CORE_RECOVERY_FAILED)
                            } else {
                                report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED)
                            }
                        }
                    }
                }
            } finally {
                monitorStarted = false
            }
        }
    }

    @Synchronized
    private fun acceptStatus(
        raw: String,
        requestId: String? = null,
        revision: Long? = null,
    ) {
        if (revision != null && !current(revision)) return
        val fields =
            raw
                .lineSequence()
                .firstOrNull()
                ?.trim()
                ?.split(" ") ?: return
        val state = runCatching { TunState.fromWire(fields.first()) }.getOrNull() ?: return
        if (!desiredRunning && state in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING)) return
        val code = fields.getOrNull(1)?.let { runCatching { RootCode.valueOf(it) }.getOrNull() }
        val warnings =
            buildList {
                if ("dns:hostname" in raw) add(RootCode.PRIVATE_DNS_STRICT.name)
                if ("always-on:yes" in raw) add(RootCode.ALWAYS_ON_VPN_CONFLICT.name)
            }
        val privateDnsMode = raw.lineSequence().firstOrNull { it.startsWith("dns:") }
        val signature = "$state:$code:$warnings:$privateDnsMode"
        if (lastRuntimeEvent == signature) return
        lastRuntimeEvent = signature
        if (state == TunState.FAILED) desiredRunning = false
        val next =
            snapshot.copy(
                state = state,
                stale = false,
                warnings = warnings,
                lastErrorCode = if (code == RootCode.CORE_RECOVERED) null else snapshot.lastErrorCode,
                lastErrorAt = if (code == RootCode.CORE_RECOVERED) null else snapshot.lastErrorAt,
            )
        publish(next, code, requestId)
        if (privateDnsMode == "dns:opportunistic" && lastPrivateDnsMode != privateDnsMode) {
            publish(snapshot, RootCode.PRIVATE_DNS_AUTO_TAKEN_OVER, requestId)
        }
        lastPrivateDnsMode = privateDnsMode
    }

    @Synchronized
    private fun report(
        revision: Long,
        next: RootSnapshot,
        code: RootCode? = null,
        requestId: String? = null,
    ) {
        if (current(revision)) publish(next, code, requestId)
    }

    @Synchronized
    private fun current(revision: Long): Boolean = snapshot.intentRevision == revision

    @Synchronized
    private fun publish(
        next: RootSnapshot,
        code: RootCode? = null,
        requestId: String? = null,
    ) {
        val now = System.currentTimeMillis()
        if (code != null && next.state in setOf(TunState.FAILED, TunState.DEGRADED)) desiredRunning = false
        val persistent = code != null && code !in INFORMATION
        snapshot =
            next.copy(
                seq = snapshot.seq + 1,
                updatedAt = now,
                lastErrorCode = if (persistent) code?.name else next.lastErrorCode,
                lastErrorAt = if (persistent) now else next.lastErrorAt,
            )
        val event =
            mapOf(
                "schemaVersion" to 1,
                "epoch" to snapshot.epoch,
                "seq" to snapshot.seq,
                "kind" to "snapshot",
                "requestId" to requestId,
                "code" to code?.name,
                "at" to now,
                "snapshot" to snapshot.toMap(),
            )
        history.addLast(event)
        if (history.size > 256) history.removeFirst()
        logs.addLast(
            mapOf(
                "cursor" to snapshot.seq.toString(),
                "at" to now,
                "level" to if (persistent) "error" else "info",
                "code" to code?.name,
                "message" to "${snapshot.state.wire} ${code?.name.orEmpty()}",
            ),
        )
        if (logs.size > 500) logs.removeFirst()
        val saved = snapshot
        scope.launch {
            operationsForPersistence.withLock {
                if (saved.epoch != snapshot.epoch || saved.seq < snapshot.seq) return@withLock
                val output = stateFile.startWrite()
                try {
                    output.write(gson.toJson(saved).toByteArray())
                    stateFile.finishWrite(output)
                } catch (_: Exception) {
                    stateFile.failWrite(output)
                }
            }
        }
        listener?.let { sink -> deliver(sink, event) }
        RootTunService.update(context, snapshot)
    }

    private val operationsForPersistence = Mutex()

    @Synchronized
    fun getLogs(
        cursor: String?,
        limit: Int,
    ): Map<String, Any?> {
        require(limit in 1..500) { "limit must be 1..500" }
        val after = cursor?.toLongOrNull() ?: -1
        val valid = logs.any { it["cursor"] == cursor }
        val available = logs.filter { !valid || (it["cursor"] as String).toLong() > after }
        val entries = available.take(limit)
        return mapOf(
            "sourcePath" to "${RootRuntime.BASE}/logs",
            "entries" to entries,
            "nextCursor" to entries.lastOrNull()?.get("cursor"),
            "eof" to (available.size <= limit),
        )
    }

    suspend fun exportDiagnostics(): File =
        withContext(Dispatchers.IO) {
            RootDiagnostics.export(context, snapshot, getLogs(null, 500), runtime)
        }

    private fun installedManager(): String? {
        val candidates =
            linkedMapOf(
                "me.weishu.kernelsu" to "kernelsu",
                "com.rifsxd.ksunext" to "kernelsu",
                "me.weishu.kernelsu.next" to "kernelsu",
                "com.sukisu.ultra" to "kernelsu",
                "com.bmax121.apatch" to "apatch",
                "com.topjohnwu.magisk" to "magisk",
            )
        return candidates.entries
            .firstOrNull { (name, _) ->
                runCatching { context.packageManager.getApplicationInfo(name, 0) }.isSuccess
            }?.value
    }

    companion object {
        private val STOP_REASONS = setOf("proxyStop", "disable", "switchToVpn", "cancelAuth", "acknowledgeFailure")
        private val PREREQUISITES = setOf(RootCode.ROOT_NOT_FOUND, RootCode.ROOT_MANAGER_UNSUPPORTED, RootCode.ANDROID_VERSION_UNSUPPORTED)
        private val INFORMATION =
            setOf(
                RootCode.MODE_SWITCHING,
                RootCode.CORE_RECOVERED,
                RootCode.PRIVATE_DNS_AUTO_TAKEN_OVER,
                RootCode.LAST_SESSION_ABNORMAL_EXIT,
            )
    }
}
