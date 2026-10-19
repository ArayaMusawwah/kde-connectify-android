package app.linksy.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import app.linksy.MainActivity
import app.linksy.R

/// Keeps a screen or camera share going while the user is in other apps,
/// with a notification that says so and can stop it.
class ShareService : Service() {
    private val shares = mutableMapOf<String, Share>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val session = intent?.getStringExtra(EXTRA_SESSION) ?: return START_NOT_STICKY
        when (intent.action) {
            ACTION_START -> start(intent, session)
            ACTION_STOP -> stop(session)
        }
        return START_NOT_STICKY
    }

    private fun start(intent: Intent, session: String) {
        val kind = intent.getStringExtra(EXTRA_KIND) ?: return
        val peer = intent.getStringExtra(EXTRA_PEER) ?: "Your computer"
        val screen = kind == "screen"
        val text = if (screen) "Sharing your screen with $peer" else "$peer is using your camera"
        // Android 14: foreground with the right type before touching the
        // projection or the camera.
        val type = if (screen) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(text, session), type)
        else startForeground(NOTIFICATION, notification(text, session))

        val onEnded = { stopFromAnyThread(session) }
        try {
            shares[session] = if (screen) {
                val data = consents.remove(session) ?: error("no screen capture consent")
                val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val projection = manager.getMediaProjection(data.first, data.second) ?: error("screen capture refused")
                ScreenShare(this, projection, session, onEnded)
            } else {
                CameraShare(this, session, onEnded)
            }
        } catch (e: Exception) {
            Log.w("linksy", "couldn't start sharing", e)
            stop(session)
        }
    }

    private fun stopFromAnyThread(session: String) {
        startService(Intent(this, ShareService::class.java).setAction(ACTION_STOP).putExtra(EXTRA_SESSION, session))
    }

    private fun stop(session: String) {
        shares.remove(session)?.let { runCatching { it.stop() } }
        NativeSession.finish(session)
        if (shares.isEmpty()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onDestroy() {
        shares.keys.toList().forEach(::stop)
        super.onDestroy()
    }

    private fun notification(text: String, session: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Screen and camera sharing", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, session.hashCode(),
            Intent(this, ShareService::class.java).setAction(ACTION_STOP).putExtra(EXTRA_SESSION, session),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_linksy)
            .setContentTitle("Linksy")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop sharing", stop).build())
            .build()
    }

    companion object {
        private const val CHANNEL = "sharing"
        private const val NOTIFICATION = 7
        private const val ACTION_START = "app.linksy.START_SHARE"
        private const val ACTION_STOP = "app.linksy.STOP_SHARE"
        private const val EXTRA_SESSION = "session"
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_PEER = "peer"

        /// Screen capture consents (result code, data) by session, from the
        /// system prompt until the share starts.
        val consents = mutableMapOf<String, Pair<Int, Intent>>()

        fun start(context: Context, session: String, kind: String, peer: String) {
            val intent = Intent(context, ShareService::class.java).setAction(ACTION_START)
                .putExtra(EXTRA_SESSION, session).putExtra(EXTRA_KIND, kind).putExtra(EXTRA_PEER, peer)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context, session: String) {
            context.startService(Intent(context, ShareService::class.java).setAction(ACTION_STOP).putExtra(EXTRA_SESSION, session))
        }
    }
}
