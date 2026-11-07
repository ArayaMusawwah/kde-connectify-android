package org.kde.connectify

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.util.Base64
import android.util.Log
import android.view.KeyEvent
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject

class MediaNotificationListener : NotificationListenerService() {
    companion object {
        @Volatile var instance: MediaNotificationListener? = null
        private val seq = AtomicLong(1)

        fun isPermissionGranted(context: Context): Boolean {
            val enabled = android.provider.Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            )
            return enabled?.contains(context.packageName) == true
        }

        fun sendCommand(player: String, action: String, positionMs: Long?): Boolean {
            return instance?.executeCommand(player, action, positionMs) ?: false
        }

        fun triggerBroadcast() {
            instance?.broadcastCurrentState()
        }
    }

    private var sessionManager: MediaSessionManager? = null
    private val controllers = mutableListOf<MediaController>()

    private var lastBroadcastTitle = ""
    private var lastBroadcastArtist = ""
    private var lastBroadcastPlaying = false
    private var lastBroadcastTime = 0L

    private var cachedTrackKey = ""
    private var cachedBase64Art: String? = null

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            val isPlaying = state?.state == PlaybackState.STATE_PLAYING
            val now = SystemClock.elapsedRealtime()
            if (isPlaying != lastBroadcastPlaying || now - lastBroadcastTime > 8000L) {
                broadcastCurrentState()
            }
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
            val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
            if (title != lastBroadcastTitle || artist != lastBroadcastArtist) {
                broadcastCurrentState()
            }
        }

        override fun onSessionDestroyed() {
            updateControllers()
        }
    }

    private val sessionsChangedListener = MediaSessionManager.OnActiveSessionsChangedListener {
        updateControllers()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        sessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        try {
            val component = ComponentName(this, MediaNotificationListener::class.java)
            sessionManager?.addOnActiveSessionsChangedListener(sessionsChangedListener, component)
            updateControllers()
        } catch (e: Exception) {
            Log.w("KDEConnectify", "Failed to add active sessions listener: ${e.message}")
        }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
        try {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun updateControllers() {
        try {
            val component = ComponentName(this, MediaNotificationListener::class.java)
            val active = sessionManager?.getActiveSessions(component) ?: emptyList()
            for (c in controllers) {
                c.unregisterCallback(callback)
            }
            controllers.clear()
            controllers.addAll(active)
            for (c in controllers) {
                c.registerCallback(callback)
            }
            broadcastCurrentState()
        } catch (e: Exception) {
            Log.w("KDEConnectify", "Error updating controllers: ${e.message}")
        }
    }

    fun broadcastCurrentState() {
        try {
            val playersArray = JSONArray()
            var primaryPlaying = false
            var primaryTitle = ""
            var primaryArtist = ""

            for (c in controllers) {
                val meta = c.metadata
                val state = c.playbackState
                val title = meta?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
                if (title.isEmpty()) continue

                val artist = meta?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
                val album = meta?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
                val duration = meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
                val isPlaying = state?.state == PlaybackState.STATE_PLAYING
                val position = state?.position ?: 0L
                val actions = state?.actions ?: 0L

                primaryPlaying = isPlaying
                primaryTitle = title
                primaryArtist = artist

                val obj = JSONObject()
                obj.put("id", c.packageName)
                val appLabel = try {
                    val appInfo = packageManager.getApplicationInfo(c.packageName, 0)
                    packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    c.packageName
                }
                obj.put("app", appLabel)
                obj.put("title", title)
                obj.put("artist", artist)
                obj.put("album", album)
                obj.put("playing", isPlaying)
                obj.put("position_ms", if (position >= 0) position else 0L)
                if (duration > 0) {
                    obj.put("length_ms", duration)
                }
                obj.put("can_next", (actions and PlaybackState.ACTION_SKIP_TO_NEXT) != 0L)
                obj.put("can_previous", (actions and PlaybackState.ACTION_SKIP_TO_PREVIOUS) != 0L)
                obj.put("can_seek", (actions and PlaybackState.ACTION_SEEK_TO) != 0L)

                // Cached Album Art
                val trackKey = "${c.packageName}:$title:$artist"
                val b64 = if (trackKey == cachedTrackKey && cachedBase64Art != null) {
                    cachedBase64Art
                } else {
                    val artBitmap = meta?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                        ?: meta?.getBitmap(MediaMetadata.METADATA_KEY_ART)
                    cachedTrackKey = trackKey
                    cachedBase64Art = artBitmap?.let { scaleAndEncodeBitmap(it) }
                    cachedBase64Art
                }
                if (b64 != null) {
                    obj.put("art", b64)
                }
                playersArray.put(obj)
            }

            lastBroadcastTitle = primaryTitle
            lastBroadcastArtist = primaryArtist
            lastBroadcastPlaying = primaryPlaying
            lastBroadcastTime = SystemClock.elapsedRealtime()

            val rootObj = JSONObject()
            rootObj.put("seq", seq.getAndIncrement())
            rootObj.put("players", playersArray)

            NativeMedia.broadcastMediaState(rootObj.toString())
        } catch (e: Exception) {
            Log.w("KDEConnectify", "Error broadcasting media state: ${e.message}")
        }
    }

    private fun scaleAndEncodeBitmap(bm: Bitmap): String? {
        return try {
            val maxSide = 300
            val scaled = if (bm.width > maxSide || bm.height > maxSide) {
                val factor = maxSide.toFloat() / maxOf(bm.width, bm.height)
                Bitmap.createScaledBitmap(bm, (bm.width * factor).toInt(), (bm.height * factor).toInt(), true)
            } else {
                bm
            }
            val stream = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 75, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    fun executeCommand(player: String, action: String, positionMs: Long?): Boolean {
        val ctrl = controllers.firstOrNull { it.packageName == player } ?: controllers.firstOrNull() ?: return false
        Log.i("KDEConnectify", "executeCommand: $action for ${ctrl.packageName}")
        when (action) {
            "play" -> ctrl.transportControls.play()
            "pause" -> ctrl.transportControls.pause()
            "play_pause" -> {
                val isPlaying = ctrl.playbackState?.state == PlaybackState.STATE_PLAYING
                if (isPlaying) ctrl.transportControls.pause() else ctrl.transportControls.play()
            }
            "next" -> ctrl.transportControls.skipToNext()
            "previous" -> ctrl.transportControls.skipToPrevious()
            "seek" -> positionMs?.let { ctrl.transportControls.seekTo(it) }
            else -> return false
        }
        broadcastCurrentState()
        return true
    }

    private fun sendMediaKey(ctrl: MediaController, keyCode: Int) {
        try {
            ctrl.dispatchMediaButtonEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            ctrl.dispatchMediaButtonEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
        } catch (e: Exception) {
            Log.w("KDEConnectify", "sendMediaKey error: ${e.message}")
        }
    }
}
