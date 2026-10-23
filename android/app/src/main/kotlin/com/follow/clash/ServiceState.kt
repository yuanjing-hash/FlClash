package com.follow.clash

import com.follow.clash.common.GlobalState
import com.follow.clash.models.SharedState
import com.follow.clash.root.RootTunController
import com.follow.clash.root.TunState
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import kotlin.coroutines.resume

object ServiceState {
    private val machine = ServiceStateMachine(AndroidServiceStateHost)
    internal val rootTun by lazy {
        RootTunController(
            GlobalState.application,
            stopVpn = { machine.requestStop().await() && ServiceController.runtime == null },
            requestNotificationPermission = {
                suspendCancellableCoroutine { continuation ->
                    val app = AndroidServiceStateHost.app()
                    if (app == null) {
                        continuation.resume(true)
                    } else {
                        app.requestNotificationPermission { permitted ->
                            if (continuation.isActive) continuation.resume(permitted)
                        }
                    }
                }
            },
            selections = {
                AndroidServiceStateHost
                    .loadSharedState()
                    .setupParams
                    ?.selectedMap
                    .orEmpty()
            },
        )
    }

    val runState = machine.runState

    val isRunRequested: Boolean
        get() = if (rootTun.selected) rootTun.runningRequested else machine.isRunRequested

    fun attachFlutterEngine(engine: FlutterEngine) = AndroidServiceStateHost.attachFlutterEngine(engine)

    fun detachFlutterEngine(engine: FlutterEngine) = AndroidServiceStateHost.detachFlutterEngine(engine)

    suspend fun handleToggleAction() {
        if (rootTun.selected) {
            if (rootTun.runningRequested) handleStopAction() else handleStartAction()
        } else {
            machine.handleToggleAction()
        }
    }

    suspend fun handleStartAction() {
        if (rootTun.selected) {
            rootTun.command("start", mapOf("requestId" to UUID.randomUUID().toString()))
        } else {
            machine.handleStartAction()
        }
    }

    suspend fun handleStopAction() {
        if (rootTun.selected) {
            rootTun.command("stop", mapOf("requestId" to UUID.randomUUID().toString(), "reason" to "proxyStop"))
        } else {
            machine.handleStopAction()
        }
    }

    suspend fun handleVpnRevokeAction() = machine.handleVpnRevokeAction()

    suspend fun awaitRunTime(): Long =
        if (rootTun.selected) {
            rootTun.snapshot.startedAt?.takeIf { rootTun.snapshot.state == TunState.RUNNING } ?: 0L
        } else {
            machine.awaitRunTime()
        }

    fun requestStart(): Deferred<Boolean> = if (rootTun.selected) CompletableDeferred(false) else machine.requestStart()

    fun requestStop(): Deferred<Boolean> {
        if (!rootTun.selected) return machine.requestStop()
        rootTun.command("stop", mapOf("requestId" to UUID.randomUUID().toString(), "reason" to "proxyStop"))
        return CompletableDeferred(true)
    }

    fun syncSharedState(state: SharedState) = machine.syncSharedState(state)

    internal fun captureRequestToken(): RunRequest = machine.captureRequestToken()

    internal suspend fun handleServiceLost(token: RunRequest) = machine.handleServiceLost(token)
}
