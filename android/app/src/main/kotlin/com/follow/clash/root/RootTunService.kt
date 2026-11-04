package com.follow.clash.root

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import com.follow.clash.MainActivity
import com.follow.clash.R
import com.follow.clash.ServiceState
import com.follow.clash.common.receiveBroadcastFlow
import com.follow.clash.core.Core
import com.follow.clash.service.models.getSpeedTrafficText
import com.follow.clash.service.modules.NetworkObserveModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch
import java.util.UUID

internal val RootSnapshot.needsForegroundService: Boolean
    get() =
        mode == "rootTun" &&
            rootTunEnabled &&
            state in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING, TunState.STOPPING)

class RootTunService : Service() {
    private val network = NetworkObserveModule(this, Core::updateDnsCapture)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var trafficText = ""

    override fun onCreate() {
        super.onCreate()
        active = this
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(
            NotificationChannel(CHANNEL, "Root TUN", NotificationManager.IMPORTANCE_LOW),
        )
        startForeground(ID, notification(this, ServiceState.rootTun.snapshot))
        ServiceState.rootTun.attachCore()
        network.start()
        scope.launch {
            receiveBroadcastFlow(exported = true) {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }.map { it.action != Intent.ACTION_SCREEN_OFF }
                .onStart { emit(getSystemService(PowerManager::class.java)?.isInteractive ?: true) }
                .collectLatest { screenOn ->
                    if (!screenOn) return@collectLatest
                    while (true) {
                        val snapshot = ServiceState.rootTun.snapshot
                        val speed =
                            if (snapshot.state == TunState.RUNNING && !snapshot.stale) {
                                Core.getSpeedTrafficText(ServiceState.currentSharedState.onlyStatisticsProxy)
                            } else {
                                ""
                            }
                        currentCoroutineContext().ensureActive()
                        trafficText = speed
                        update()
                        delay(1_000)
                    }
                }
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (intent?.action == ACTION_STOP) {
            ServiceState.rootTun.command("stop", mapOf("requestId" to UUID.randomUUID().toString(), "reason" to "proxyStop"))
            return START_NOT_STICKY
        }
        if (!ServiceState.rootTun.snapshot.needsForegroundService) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (active === this) active = null
        scope.cancel()
        network.stop()
        super.onDestroy()
    }

    private fun updateNotification() {
        if (active !== this) return
        val snapshot = ServiceState.rootTun.snapshot
        if (!snapshot.needsForegroundService && !snapshot.stale) {
            stopSelf()
            return
        }
        getSystemService(NotificationManager::class.java)?.notify(ID, notification(this, snapshot))
    }

    internal companion object {
        private const val CHANNEL = "flclash-root-tun"
        private const val ID = 20220
        private const val ACTION_STOP = "rootTunStop"

        @Volatile private var active: RootTunService? = null

        fun start(context: Context) {
            val intent = Intent(context, RootTunService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RootTunService::class.java))
        }

        fun update() {
            val service = active ?: return
            service.main.post { service.updateNotification() }
        }

        private fun notification(
            context: Context,
            snapshot: RootSnapshot,
        ): Notification {
            val open =
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            val stop =
                PendingIntent.getService(
                    context,
                    1,
                    Intent(context, RootTunService::class.java).setAction(ACTION_STOP),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            val label =
                context.resources.getIdentifier(
                    "root_tun_${(snapshot.lastErrorCode ?: snapshot.warnings.firstOrNull())?.lowercase() ?: snapshot.state.wire.lowercase()}",
                    "string",
                    context.packageName,
                )
            val text = if (label != 0) context.getString(label) else snapshot.state.wire
            val speed =
                active
                    ?.trafficText
                    .orEmpty()
                    .takeIf { snapshot.state == TunState.RUNNING && !snapshot.stale }
                    .orEmpty()
            val content = listOf(speed, text).filter(String::isNotBlank).joinToString("\n")
            val shared = ServiceState.currentSharedState
            val builder =
                Notification
                    .Builder(context, CHANNEL)
                    .setSmallIcon(com.follow.clash.service.R.drawable.ic_service)
                    .setContentTitle("${shared.currentProfileName} · Root TUN")
                    .setContentText(speed.ifBlank { text })
                    .setStyle(Notification.BigTextStyle().bigText(content))
                    .setContentIntent(open)
                    .setOnlyAlertOnce(true)
                    .setCategory(Notification.CATEGORY_SERVICE)
                    .setOngoing(snapshot.needsForegroundService)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            if (shared.showStopAction) {
                builder.addAction(Notification.Action.Builder(null, shared.stopText, stop).build())
            }
            return builder.build()
        }
    }
}
