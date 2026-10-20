package app.linksy

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/// "Ring my phone" (docs/protocol.md §4.5, `ring`): the alarm sound, looping, at full
/// alarm volume, which plays on silent too. The volume goes back to what it
/// was on stop. No permission needed beyond vibrating.
class RingPlayer(private val context: Context) {
    private var player: MediaPlayer? = null
    private var savedVolume: Int? = null

    private val audio get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val vibrator: Vibrator
        get() = if (Build.VERSION.SDK_INT >= 31) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    fun start() {
        if (player != null) return
        val audio = audio
        runCatching {
            savedVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        }
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(context, sound)
                isLooping = true
                prepare()
                start()
            }
        }.onFailure { Log.w("linksy", "couldn't play the ring sound", it) }.getOrNull()
        runCatching {
            vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0))
        }
    }

    fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        runCatching { vibrator.cancel() }
        savedVolume?.let { runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, it, 0) } }
        savedVolume = null
    }
}
