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
            ACTION_SWITCH -> (shares[session] as? CameraShare)?.switch()
        }
        return START_NOT_STICKY
    }

    private fun start(intent: Intent, session: String) {
        val kind = intent.getStringExtra(EXTRA_KIND) ?: return
        val peer = intent.getStringExtra(EXTRA_PEER) ?: "Your computer"
        active[session] = mapOf("session" to session, "kind" to kind, "peer" to (intent.getStringExtra(EXTRA_PEER_ID) ?: ""))
        val screen = kind == "screen" || kind == "control"
        val mic = kind == "microphone"
        val text = when {
            screen -> "Sharing your screen with $peer"
            mic -> "$peer is using your microphone"
            else -> "$peer is using your camera"
        }
        kinds[session] = kind
        // Android 14: foreground with the right type before touching the
        // projection, camera or microphone; every running share's type.
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(text, session, kind == "camera"), foregroundType())
        else startForeground(NOTIFICATION, notification(text, session, kind == "camera"))

        val onEnded = { stopFromAnyThread(session) }
        try {
            val share = when {
                screen -> {
                    val data = consents.remove(session) ?: error("no screen capture consent")
                    val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val projection = manager.getMediaProjection(data.first, data.second) ?: error("screen capture refused")
                    ScreenShare(this, projection, session, onEnded)
                }
                mic -> MicShare(session, onEnded)
                else -> CameraShare(this, session, onEnded).also { camera ->
                    webcams[session] = camera
                    camera.onState = { state ->
                        webcamListener?.invoke(session, state)
                        // The computer's camera controls follow it too (docs/android-app.md §2.8).
                        NativeSession.cameraState(session, state.toString())
                    }
                }
            }
            shares[session] = share
        } catch (e: Exception) {
            Log.w("linksy", "couldn't start sharing", e)
            stop(session)
        }
    }

    /// Running shares by session → kind, for the foreground service type.
    private val kinds = mutableMapOf<String, String>()

    private fun foregroundType(): Int {
        var type = 0
        for (k in kinds.values) {
            type = type or when (k) {
                "screen", "control" -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                "microphone" -> if (Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
                else -> if (Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0
            }
        }
        return if (type == 0 && Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else type
    }

    private fun stopFromAnyThread(session: String) {
        startService(Intent(this, ShareService::class.java).setAction(ACTION_STOP).putExtra(EXTRA_SESSION, session))
    }

    private fun stop(session: String) {
        webcams.remove(session)
        active.remove(session)
        kinds.remove(session)
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

    private fun notification(text: String, session: String, camera: Boolean = false): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Screen and camera sharing", NotificationManager.IMPORTANCE_LOW),
            )
        }
        // A webcam's notification opens its controls.
        val open = PendingIntent.getActivity(
            this, session.hashCode() + 2,
            Intent(this, MainActivity::class.java).apply { if (camera) putExtra(EXTRA_WEBCAM, session) }
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
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
            .apply {
                if (camera) {
                    val switch = PendingIntent.getService(
                        this@ShareService, session.hashCode() + 1,
                        Intent(this@ShareService, ShareService::class.java).setAction(ACTION_SWITCH).putExtra(EXTRA_SESSION, session),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    )
                    addAction(Notification.Action.Builder(null, "Switch camera", switch).build())
                }
            }
            .build()
    }

    companion object {
        private const val CHANNEL = "sharing"
        private const val NOTIFICATION = 7
        private const val ACTION_START = "app.linksy.START_SHARE"
        private const val ACTION_STOP = "app.linksy.STOP_SHARE"
        private const val ACTION_SWITCH = "app.linksy.SWITCH_CAMERA"
        const val EXTRA_WEBCAM = "app.linksy.webcam"
        private const val EXTRA_SESSION = "session"
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_PEER = "peer"
        private const val EXTRA_PEER_ID = "peer_id"

        /// What runs now (session, kind, peer id), for an app that restarts
        /// mid-share to find its shares again.
        val active = java.util.concurrent.ConcurrentHashMap<String, Map<String, String>>()

        /// Screen capture consents (result code, data) by session, from the
        /// system prompt until the share starts.
        val consents = mutableMapOf<String, Pair<Int, Intent>>()

        /// Running webcams, by session, for the phone's camera controls.
        val webcams = java.util.concurrent.ConcurrentHashMap<String, CameraShare>()

        /// Hears every webcam change (session, state), while the app shows them.
        @Volatile var webcamListener: ((String, org.json.JSONObject) -> Unit)? = null

        fun start(context: Context, session: String, kind: String, peer: String, peerId: String) {
            val intent = Intent(context, ShareService::class.java).setAction(ACTION_START)
                .putExtra(EXTRA_SESSION, session).putExtra(EXTRA_KIND, kind).putExtra(EXTRA_PEER, peer)
                .putExtra(EXTRA_PEER_ID, peerId)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        /// Front ↔ back camera for a webcam session.
        fun switchCamera(context: Context, session: String) {
            context.startService(Intent(context, ShareService::class.java).setAction(ACTION_SWITCH).putExtra(EXTRA_SESSION, session))
        }

        fun stop(context: Context, session: String) {
            context.startService(Intent(context, ShareService::class.java).setAction(ACTION_STOP).putExtra(EXTRA_SESSION, session))
        }
    }
}
