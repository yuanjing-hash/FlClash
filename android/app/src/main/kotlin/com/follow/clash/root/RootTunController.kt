package com.follow.clash.root

import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.AtomicFile
import android.util.Log
import com.follow.clash.BuildConfig
import com.google.gson.GsonBuilder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
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
    private val requestNotificationPermission: suspend () -> Boolean,
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

    @Volatile private var authorizationMonitorStarted = false
    private var authorizationChannel: RootAuthorizationChannel? = null
    private var lastRuntimeEvent = ""
    private var lastPrivateDnsMode: String? = null
    private val reconciliationPolling = ReconciliationPolling()

    @Volatile private var autostartRequestId: String? = null

    @Volatile
    var snapshot: RootSnapshot =
        RootReconciliation.initial(
            if (stateFile.baseFile.exists()) {
                runCatching {
                    stateFile.openRead().use { gson.fromJson(it.reader(), RootSnapshot::class.java) }
                }.getOrDefault(RootSnapshot())
            } else {
                null
            },
        )
        private set

    @Volatile private var runtimeMayExist = snapshot.rootTunEnabled && snapshot.stale
    private var authorizationWasGranted = snapshot.authStatus in setOf("granted", "revoked")

    @Synchronized
    private fun authChannel(): RootAuthorizationChannel =
        authorizationChannel ?: RootAuthorizationChannel(context.filesDir).also { authorizationChannel = it }

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
        val requestId = requireRequestId(arguments["requestId"])
        val reason = if (method == "stop") arguments["reason"] as? String else null
        val enabled = if (method == "setAutostart") arguments["enabled"] as? Boolean else null
        require(method != "setAutostart" || enabled != null) { "enabled must be a boolean" }
        val fingerprint = "$method:$reason:$enabled"
        requests[requestId]?.let { (previous, result) ->
            require(previous == fingerprint) { "requestId was reused with different parameters" }
            return result
        }
        if (method == "stop") {
            require(reason in STOP_REASONS) { "Invalid stop reason" }
            require(reason != "cancelAuth" || snapshot.state == TunState.AWAITING_AUTH) { "cancelAuth requires awaitingAuth" }
            require(reason != "acknowledgeFailure" || snapshot.state == TunState.FAILED) { "acknowledgeFailure requires failed" }
        }
        if (BuildConfig.ROOT_TUN_SAFE_MODE) {
            return remember(requestId, fingerprint, failure(RootCode.CORE_START_FAILED, method, retryable = false, reason = "SAFE_MODE"))
        }
        if (method in setOf("start", "requestAuth") && snapshot.state == TunState.DEGRADED) {
            val code = snapshot.lastErrorCode?.let { runCatching { RootCode.valueOf(it) }.getOrNull() }
            if (code in PREREQUISITES) return remember(requestId, fingerprint, failure(checkNotNull(code), "detectRoot"))
        }
        if (method == "setAutostart") {
            if (enabled == true && snapshot.authStatus == "revoked") {
                return remember(requestId, fingerprint, failure(RootCode.ROOT_PERMISSION_REVOKED, method))
            }
            require(enabled != true || snapshot.rootTunEnabled) { "ROOT_TUN_DISABLED" }
            require(enabled != true || snapshot.authStatus == "granted") { "AUTH_REQUIRED" }
        }
        val revision = if (method == "setAutostart") snapshot.intentRevision else snapshot.intentRevision + 1
        val coalesced =
            method in setOf("start", "requestAuth") && desiredRunning && !snapshot.stale &&
                snapshot.state in setOf(TunState.RUNNING, TunState.STARTING, TunState.AWAITING_AUTH, TunState.RECOVERING)
        if (!coalesced) {
            if (method != "setAutostart") reconciliationPolling.reset()
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
                "setAutostart" -> autostartRequestId = requestId
                else -> throw IllegalArgumentException("Unknown command")
            }
            scope.launch {
                operations.withLock {
                    if (!current(revision)) return@withLock
                    try {
                        when (method) {
                            "start", "requestAuth" -> authorizeAndStart(revision, requestId)
                            "recheckRoot" -> recheck(revision, requestId)
                            "setAutostart" -> {
                                if (autostartRequestId != requestId) return@withLock
                                val changed = runCatching { runtime.setAutostart(checkNotNull(enabled)) }.getOrDefault(false)
                                val actual = runCatching { runtime.autostartEnabled() }.getOrDefault(snapshot.autostartEnabled)
                                report(
                                    revision,
                                    snapshot.copy(autostartEnabled = actual),
                                    if (changed && actual == enabled) null else RootCode.AUTOSTART_FAILED,
                                    requestId,
                                )
                            }
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
                snapshot.copy(state = TunState.DEGRADED, rootManager = detected.manager, authStatus = detected.auth, stale = false),
                detected.error,
                requestId,
            )
            return
        }
        report(
            revision,
            snapshot.copy(
                state = TunState.AWAITING_AUTH,
                stale = false,
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
        if (retryRevoked(snapshot)) {
            desiredRunning = true
            report(revision, snapshot.copy(lastErrorCode = null, lastErrorAt = null), requestId = requestId)
            authorizeAndStart(revision, requestId)
            return
        }
        val root = detection.detect(Build.VERSION.SDK_INT, snapshot.authStatus)
        if (!current(revision)) return
        if (snapshot.stale || (runtimeMayExist && !desiredRunning)) {
            reconcile(revision, root, requestId)
            return
        }
        if (root.error in PREREQUISITES) {
            report(
                revision,
                snapshot.copy(state = TunState.DEGRADED, rootManager = root.manager, authStatus = root.auth, stale = false),
                root.error,
                requestId,
            )
        } else if (root.auth == "granted" && desiredRunning) {
            report(revision, snapshot.copy(rootManager = root.manager, authStatus = root.auth), requestId = requestId)
            if (snapshot.state != TunState.RUNNING || snapshot.stale) start(revision, requestId)
        } else {
            val rechecked = recheckedAuth(snapshot, root, desiredRunning)
            report(
                revision,
                rechecked,
                if (rechecked.state == TunState.AWAITING_AUTH) RootCode.ROOT_GRANT_NOT_DETECTED else null,
                requestId,
            )
        }
    }

    private fun reconcile(
        revision: Long,
        root: RootStatus,
        requestId: String? = null,
    ) {
        val status =
            if (root.manager == "magisk") {
                monitoredStatus(root.manager, authChannel().runtimeStatus) { runtime.status() } ?: run {
                    markRuntimeStale(revision, requestId)
                    startMonitor()
                    return
                }
            } else if (root.auth ==
                "granted"
            ) {
                runCatching { runtime.status() }.getOrDefault(ShellResult(1, "", "Status unavailable"))
            } else {
                null
            }
        var checked = RootReconciliation.checked(snapshot, root, status)
        if (root.manager != "magisk" && checked.state == TunState.RUNNING &&
            !runCatching { runtime.attach(root.manager, authChannel().configuration) }.getOrDefault(false)
        ) {
            checked = checked.copy(state = TunState.STOPPING, lastErrorCode = RootCode.CLEANUP_FAILED.name)
        }
        synchronized(this) {
            if (!current(revision)) return
            reconciliationPolling.reset()
            desiredRunning = checked.state in setOf(TunState.RUNNING, TunState.STARTING, TunState.RECOVERING)
            runtimeMayExist = runtimeMayExist || desiredRunning || checked.state == TunState.STOPPING
            publish(checked, checked.lastErrorCode?.let(RootCode::valueOf), requestId)
        }
        if (desiredRunning) startForegroundService()
        if (desiredRunning || checked.state == TunState.STOPPING) startMonitor()
    }

    @Synchronized
    private fun markRuntimeStale(
        revision: Long,
        requestId: String? = null,
    ) {
        if (!current(revision)) return
        reconciliationPolling.missing(SystemClock.elapsedRealtime())
        val next = staleRuntime(snapshot)
        if (next != snapshot) publish(next, RootCode.CLEANUP_FAILED, requestId)
    }

    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            RootTunService.start(context)
            return
        }
        try {
            RootTunService.start(context)
        } catch (error: ForegroundServiceStartNotAllowedException) {
            Log.w("RootTun", "Foreground service start was not allowed; root runtime continues independently", error)
        }
    }

    private suspend fun awaitNotificationPermission(revision: Long): Boolean {
        val permission = scope.async { requestNotificationPermission() }
        return try {
            while (!permission.isCompleted) {
                if (!current(revision)) return false
                delay(50)
            }
            current(revision) && permission.await()
        } finally {
            permission.cancel()
        }
    }

    private suspend fun start(
        revision: Long,
        requestId: String,
    ) {
        if (!awaitNotificationPermission(revision)) {
            report(revision, snapshot.copy(state = TunState.FAILED), RootCode.CORE_START_FAILED, requestId)
            return
        }
        if (!current(revision)) return
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
        startForegroundService()
        runtimeMayExist = true
        authorizationWasGranted = true
        runtime.start(selections(), snapshot.rootManager, { authChannel().beginSession() }) {
            current(revision) && SystemClock.elapsedRealtime() < deadline
        }
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
        startMonitor()
        while (current(revision) && SystemClock.elapsedRealtime() < deadline) {
            val status = monitoredStatus(snapshot.rootManager, authorizationChannel?.runtimeStatus) { runtime.status() }
            if (status == null) {
                delay(200)
                continue
            }
            if (status.stdout.startsWith("failed") || status.stdout.contains("CLEANUP_FAILED")) {
                acceptStatus(status.stdout, requestId, revision)
                return
            }
            if (runtime.healthy(status)) {
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
                report(
                    revision,
                    snapshot.copy(
                        state = TunState.RUNNING,
                        warnings = snapshot.warnings.filterNot { it == RootCode.CLEANUP_FAILED.name },
                        startedAt = System.currentTimeMillis(),
                        autostartEnabled =
                            "autostart:yes" in status.stdout,
                    ),
                    requestId = requestId,
                )
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
        val restoreWarning = !noRuntime && runtime.restoreDiffExists()
        if (!clean) {
            report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED, requestId)
            return
        }
        val disable = reason in setOf("disable", "switchToVpn")
        if ((disable || force) && !runtime.setAutostart(false)) {
            report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED, requestId)
            return
        }
        if ((disable || force) && !noRuntime && !runtime.delete()) {
            report(revision, snapshot.copy(state = TunState.STOPPING), RootCode.CLEANUP_FAILED, requestId)
            return
        }
        if (disable || force) {
            runtimeMayExist = false
        }
        report(
            revision,
            snapshot.copy(
                state = TunState.DISABLED,
                stale = false,
                warnings = if (restoreWarning) listOf(RootCode.CLEANUP_FAILED.name) else emptyList(),
                startedAt = null,
                rootTunEnabled = if (disable || force) false else snapshot.rootTunEnabled,
                mode =
                    if (reason == "switchToVpn") {
                        "vpn"
                    } else if (disable || force) {
                        "off"
                    } else {
                        snapshot.mode
                    },
                autostartEnabled = if (disable || force) false else snapshot.autostartEnabled,
                lastErrorCode = null,
                lastErrorAt = null,
            ),
            requestId = requestId,
        )
        if (disable || force) {
            authorizationWasGranted = false
            authorizationChannel?.close()
            authorizationChannel = null
        }
        RootTunService.stop(context)
    }

    @Synchronized
    private fun startMonitor() {
        startAuthorizationMonitor()
        if (monitorStarted) return
        monitorStarted = true
        scope.launch {
            try {
                while (true) {
                    delay(1_000)
                    operations.withLock {
                        if (!selected || (!desiredRunning && snapshot.state != TunState.STOPPING && !snapshot.stale)) return@withLock
                        val revision = snapshot.intentRevision
                        if (snapshot.stale && snapshot.rootManager == "magisk") {
                            if (reconciliationPolling.due(SystemClock.elapsedRealtime())) {
                                reconcile(revision, RootStatus(snapshot.rootManager, snapshot.authStatus))
                            }
                            return@withLock
                        }
                        val status =
                            monitoredStatus(snapshot.rootManager, authorizationChannel?.runtimeStatus) { runtime.status() }
                                ?: run {
                                    markRuntimeStale(revision)
                                    return@withLock
                                }
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
    private fun startAuthorizationMonitor() {
        if (authorizationMonitorStarted || !authorizationWasGranted) return
        authorizationMonitorStarted = true
        scope.launch {
            val probe = RootShell()
            var authorization = RootAuthorization()
            var observedRevision = -1L
            try {
                while (snapshot.rootTunEnabled) {
                    val revision = snapshot.intentRevision
                    if (revision != observedRevision) {
                        authorization = RootAuthorization()
                        observedRevision = revision
                    }
                    val channel = authChannel()
                    val verdict =
                        if (authorizationProbeAllowed(snapshot, runtimeMayExist)) {
                            authorization.probe(SystemClock.elapsedRealtime()) { probe.root("id -u", 1_000) }
                        } else {
                            "unknown"
                        }
                    if (!current(revision) || !snapshot.rootTunEnabled) continue
                    channel.verdict = verdict
                    val completed = channel.cleanupCode
                    if (completed != null) {
                        operations.withLock {
                            if (!current(revision) || !snapshot.rootTunEnabled) return@withLock
                            desiredRunning = false
                            publish(
                                snapshot.copy(
                                    state = TunState.FAILED,
                                    authStatus = "revoked",
                                    autostartEnabled = false,
                                    stale = false,
                                    warnings = emptyList(),
                                    startedAt = null,
                                    authDeadlineAt = null,
                                ),
                                completed,
                            )
                        }
                        return@launch
                    }
                    delay(2_000)
                }
            } finally {
                authorizationMonitorStarted = false
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
                if ("restore-diff:yes" in raw) add(RootCode.CLEANUP_FAILED.name)
            }
        val privateDnsMode = raw.lineSequence().firstOrNull { it.startsWith("dns:") }
        val signature = "$state:$code:$warnings:$privateDnsMode:${"autostart:yes" in raw}"
        if (lastRuntimeEvent == signature) return
        lastRuntimeEvent = signature
        if (state == TunState.FAILED) desiredRunning = false
        val next =
            snapshot.copy(
                state = state,
                stale = false,
                warnings = warnings,
                autostartEnabled = "autostart:yes" in raw,
                authStatus = if ("auth:revoked" in raw) "revoked" else snapshot.authStatus,
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

    suspend fun exportDiagnostics(requestId: Any?): Map<String, Any> {
        requireRequestId(requestId)
        return withContext(Dispatchers.IO) {
            RootDiagnostics.result(RootDiagnostics.export(context, snapshot, getLogs(null, 500), runtime))
        }
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

    init {
        if (!BuildConfig.ROOT_TUN_SAFE_MODE) startAuthorizationMonitor()
        if (snapshot.stale && !BuildConfig.ROOT_TUN_SAFE_MODE) {
            val revision = snapshot.intentRevision
            scope.launch {
                operations.withLock {
                    if (!current(revision) || !snapshot.stale) return@withLock
                    val root = detection.detect(Build.VERSION.SDK_INT, snapshot.authStatus)
                    reconcile(revision, root)
                }
            }
        }
    }

    internal class ReconciliationPolling {
        private var staleSince: Long? = null
        private var nextCheckAt = 0L

        @Synchronized
        fun missing(nowMs: Long) {
            if (staleSince == null) staleSince = nowMs
        }

        @Synchronized
        fun due(nowMs: Long): Boolean {
            missing(nowMs)
            if (nowMs < nextCheckAt) return false
            val interval = if (nowMs - checkNotNull(staleSince) >= STALE_TIMEOUT_MS) SLOW_INTERVAL_MS else 1_000L
            nextCheckAt = nowMs + interval
            return true
        }

        @Synchronized
        fun reset() {
            staleSince = null
            nextCheckAt = 0L
        }

        companion object {
            const val STALE_TIMEOUT_MS = 30_000L
            const val SLOW_INTERVAL_MS = 30_000L
        }
    }

    companion object {
        internal fun staleRuntime(previous: RootSnapshot): RootSnapshot =
            previous.copy(
                state = TunState.STOPPING,
                stale = true,
                lastErrorCode = RootCode.CLEANUP_FAILED.name,
                startedAt = null,
                authDeadlineAt = null,
            )

        internal fun monitoredStatus(
            manager: String,
            pushedStatus: String?,
            nowMs: Long = SystemClock.elapsedRealtime(),
            query: () -> ShellResult,
        ): ShellResult? = if (manager == "magisk") RootRuntimeReport.fresh(pushedStatus, nowMs)?.let { ShellResult(0, it, "") } else query()

        internal fun authorizationProbeAllowed(
            current: RootSnapshot,
            runtimeMayExist: Boolean,
        ): Boolean =
            current.rootManager != "magisk" && runtimeMayExist && current.rootTunEnabled &&
                current.authStatus != "revoked" &&
                current.state in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING, TunState.STOPPING)

        internal fun retryRevoked(previous: RootSnapshot): Boolean =
            previous.rootTunEnabled && previous.authStatus == "revoked" &&
                previous.lastErrorCode in setOf(RootCode.ROOT_PERMISSION_REVOKED.name, RootCode.AUTOSTART_ROOT_REVOKED.name)

        internal fun recheckedAuth(
            previous: RootSnapshot,
            root: RootStatus,
            desiredRunning: Boolean,
        ): RootSnapshot {
            val state =
                when {
                    root.auth != "granted" && desiredRunning -> TunState.AWAITING_AUTH
                    previous.state == TunState.DEGRADED || previous.state == TunState.AWAITING_AUTH -> TunState.DISABLED
                    else -> previous.state
                }
            return previous.copy(state = state, rootManager = root.manager, authStatus = root.auth, stale = false)
        }

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
