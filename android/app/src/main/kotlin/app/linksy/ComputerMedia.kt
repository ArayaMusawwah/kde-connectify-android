package app.linksy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock
import android.util.Base64

/// What a computer plays, as a media notification on this phone (like KDE
/// Connect's): play/pause, previous/next, 10 seconds back and forward, and a
/// seek bar. Its buttons come back to Dart as `media_command`s.
object ComputerMedia {
    private const val CHANNEL = "computer_media"
    private const val NOTIFICATION = 12
    private const val EXTRA_ACTION = "action"
    private const val BACK = "back10"
    private const val FORWARD = "forward10"

    /// A button pressed: the action (`play_pause`, `seek`…) and, for `seek`,
    /// where to.
    var onAction: ((String, Long?) -> Unit)? = null

    private var session: MediaSession? = null
    private var art: String? = null
    private var bitmap: Bitmap? = null

    /// Shows [player] (from Dart: title, artist, app, device, playing,
    /// position_ms, length_ms, can_next, can_previous, can_seek, art), or
    /// takes the notification away when null.
    fun show(context: Context, player: Map<String, Any?>?) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (player == null) {
            manager.cancel(NOTIFICATION)
            session?.release()
            session = null
            art = null
            bitmap = null
            return
        }
        val session = session ?: MediaSession(context, "linksy-computer").also {
            it.setCallback(callback)
            it.isActive = true
            session = it
        }
        val playing = player["playing"] == true
        val position = (player["position_ms"] as Number?)?.toLong()
        val length = (player["length_ms"] as Number?)?.toLong()
        val canSeek = player["can_seek"] == true
        // The cover, decoded only when it changes.
        val cover = player["art"] as String?
        if (cover != art) {
            art = cover
            bitmap = cover?.let {
                runCatching { Base64.decode(it, Base64.DEFAULT).let { b -> BitmapFactory.decodeByteArray(b, 0, b.size) } }.getOrNull()
            }
        }
        val bitmap = bitmap
        val title = (player["title"] as String?).orEmpty().ifEmpty { player["app"] as String? ?: "" }
        val artist = (player["artist"] as String?).orEmpty()
        val where = Lang.str(context, R.string.media_on, player["app"] as String? ?: "", player["device"] as String? ?: "")
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist.ifEmpty { where })
                .putString(MediaMetadata.METADATA_KEY_ALBUM, (player["album"] as String?).orEmpty())
                .apply {
                    if (length != null) putLong(MediaMetadata.METADATA_KEY_DURATION, length)
                    if (bitmap != null) putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bitmap)
                }
                .build(),
        )
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE
        if (player["can_next"] == true) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (player["can_previous"] == true) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        if (canSeek) actions = actions or PlaybackState.ACTION_SEEK_TO
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    position ?: PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    if (playing) 1f else 0f,
                    SystemClock.elapsedRealtime(),
                )
                .apply {
                    if (canSeek && position != null) {
                        addCustomAction(BACK, Lang.str(context, R.string.media_back10), R.drawable.ic_media_back10)
                        addCustomAction(FORWARD, Lang.str(context, R.string.media_forward10), R.drawable.ic_media_forward10)
                    }
                }
                .build(),
        )

        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, Lang.str(context, R.string.channel_computer_media), NotificationManager.IMPORTANCE_LOW),
            )
        }
        // Android before 13 draws these buttons; 13 and later the session's.
        fun button(icon: Int, label: Int, action: String) = Notification.Action.Builder(
            Icon.createWithResource(context, icon),
            Lang.str(context, label),
            PendingIntent.getBroadcast(
                context, action.hashCode(),
                Intent(context, Button::class.java).putExtra(EXTRA_ACTION, action),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        ).build()
        val buttons = listOfNotNull(
            if (player["can_previous"] == true) button(android.R.drawable.ic_media_previous, R.string.media_previous, "previous") else null,
            if (playing) {
                button(android.R.drawable.ic_media_pause, R.string.media_pause, "play_pause")
            } else {
                button(android.R.drawable.ic_media_play, R.string.media_play, "play_pause")
            },
            if (player["can_next"] == true) button(android.R.drawable.ic_media_next, R.string.media_next, "next") else null,
        )
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        buttons.forEach(builder::addAction)
        manager.notify(
            NOTIFICATION,
            builder
                .setSmallIcon(R.drawable.ic_stat_linksy)
                .setContentTitle(title)
                .setContentText(if (artist.isEmpty()) where else "$artist · $where")
                .setLargeIcon(bitmap)
                .setContentIntent(open)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setStyle(
                    Notification.MediaStyle()
                        .setMediaSession(session.sessionToken)
                        .setShowActionsInCompactView(*buttons.indices.toList().toIntArray()),
                )
                .build(),
        )
    }

    /// Where the player is now, guessed from where it was and since when.
    private fun now(): Long? {
        val state = session?.controller?.playbackState ?: return null
        if (state.position < 0) return null
        val since = SystemClock.elapsedRealtime() - state.lastPositionUpdateTime
        return state.position + (since * state.playbackSpeed).toLong()
    }

    private fun skip(by: Long) {
        val at = now() ?: return
        val length = session?.controller?.metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION)?.takeIf { it > 0 }
        val to = (at + by).coerceAtLeast(0).let { if (length != null) it.coerceAtMost(length) else it }
        onAction?.invoke("seek", to)
    }

    private val callback = object : MediaSession.Callback() {
        override fun onPlay() { onAction?.invoke("play", null) }
        override fun onPause() { onAction?.invoke("pause", null) }
        override fun onSkipToNext() { onAction?.invoke("next", null) }
        override fun onSkipToPrevious() { onAction?.invoke("previous", null) }
        override fun onSeekTo(pos: Long) { onAction?.invoke("seek", pos) }
        override fun onCustomAction(action: String, extras: android.os.Bundle?) {
            when (action) {
                BACK -> skip(-10_000)
                FORWARD -> skip(10_000)
            }
        }
    }

    class Button : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            intent.getStringExtra(EXTRA_ACTION)?.let { onAction?.invoke(it, null) }
        }
    }
}
