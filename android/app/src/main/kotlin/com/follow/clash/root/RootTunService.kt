package com.follow.clash.root

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import com.follow.clash.MainActivity
import com.follow.clash.R
import com.follow.clash.ServiceState
import java.util.UUID

class RootTunService : Service() {
    override fun onCreate() {
        super.onCreate()
        active = true
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(
            NotificationChannel(CHANNEL, "Root TUN", NotificationManager.IMPORTANCE_LOW),
        )
        startForeground(ID, notification(this, ServiceState.rootTun.snapshot))
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (intent?.action == ACTION_STOP) {
            ServiceState.rootTun.command("stop", mapOf("requestId" to UUID.randomUUID().toString(), "reason" to "proxyStop"))
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        active = false
        super.onDestroy()
    }

    internal companion object {
        private const val CHANNEL = "flclash-root-tun"
        private const val ID = 20220
        private const val ACTION_STOP = "rootTunStop"

        @Volatile private var active = false

        fun start(context: Context) {
            val intent = Intent(context, RootTunService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RootTunService::class.java))
        }

        fun update(
            context: Context,
            snapshot: RootSnapshot,
        ) {
            if (!active) return
            context.getSystemService(NotificationManager::class.java)?.notify(ID, notification(context, snapshot))
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
            return Notification
                .Builder(context, CHANNEL)
                .setSmallIcon(com.follow.clash.service.R.drawable.ic_service)
                .setContentTitle("FlClash Root TUN")
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setOnlyAlertOnce(true)
                .setOngoing(snapshot.state in setOf(TunState.STARTING, TunState.RUNNING, TunState.RECOVERING, TunState.STOPPING))
                .addAction(Notification.Action.Builder(null, context.getString(R.string.root_tun_stop), stop).build())
                .build()
        }
    }
}
