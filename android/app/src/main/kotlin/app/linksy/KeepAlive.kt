package app.linksy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/// Keeps Linksy running with the screen off, with a quiet notification that
/// says why: while a computer locks itself when this phone leaves (its
/// heartbeats must keep coming, docs/protocol.md §4.5), or while a computer browses
/// this phone's files. Holds the CPU awake only for heartbeats.
class KeepAlive : Service() {
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Linksy is connected"
        val note = notification(text)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION, note)
        }
        val awake = intent?.getBooleanExtra(EXTRA_AWAKE, false) == true
        if (awake && wake == null) {
            wake = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "linksy:heartbeats")
                .apply { setReferenceCounted(false); acquire() }
        } else if (!awake) {
            release()
        }
        return START_NOT_STICKY
    }

    private fun release() {
        wake?.takeIf { it.isHeld }?.release()
        wake = null
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }

    private fun notification(text: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, Lang.str(this, R.string.channel_staying), NotificationManager.IMPORTANCE_MIN),
            )
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_linksy)
            .setContentTitle("Linksy")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val CHANNEL = "connected"
        private const val NOTIFICATION = 8
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_AWAKE = "awake"

        /// Starts or updates it; [awake] keeps the CPU on (heartbeats).
        fun start(context: Context, text: String, awake: Boolean) {
            val intent = Intent(context, KeepAlive::class.java).putExtra(EXTRA_TEXT, text).putExtra(EXTRA_AWAKE, awake)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KeepAlive::class.java))
        }
    }
}
