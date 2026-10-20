package app.linksy

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/// Whether a call rings, goes on, or is over, from the audio mode: no phone
/// permission needed, and calls in other apps (WhatsApp…) count too.
/// Reports `ringing`, `active` or `idle` on changes.
class CallWatcher(private val context: Context, private val onState: (String) -> Unit) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var last = state(audio.mode)
    private var listener: Any? = null
    private val poll = object : Runnable {
        override fun run() {
            changed(audio.mode)
            main.postDelayed(this, 1000)
        }
    }

    fun start() {
        if (Build.VERSION.SDK_INT >= 31) {
            val l = AudioManager.OnModeChangedListener { mode -> main.post { changed(mode) } }
            audio.addOnModeChangedListener(context.mainExecutor, l)
            listener = l
        } else {
            main.post(poll)
        }
    }

    fun stop() {
        if (Build.VERSION.SDK_INT >= 31) {
            (listener as? AudioManager.OnModeChangedListener)?.let { audio.removeOnModeChangedListener(it) }
        } else {
            main.removeCallbacks(poll)
        }
        listener = null
    }

    private fun changed(mode: Int) {
        val now = state(mode)
        if (now != last) {
            last = now
            onState(now)
        }
    }

    private fun state(mode: Int) = when (mode) {
        AudioManager.MODE_RINGTONE -> "ringing"
        AudioManager.MODE_IN_CALL, AudioManager.MODE_IN_COMMUNICATION -> "active"
        else -> "idle"
    }
}
