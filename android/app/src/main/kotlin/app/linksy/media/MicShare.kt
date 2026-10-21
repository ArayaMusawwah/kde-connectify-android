package app.linksy.media

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log

/// The phone as a computer's microphone (docs/protocol.md §4.8 `microphone`): raw
/// 16-bit little-endian PCM, 48 kHz mono, in 10 ms chunks, nothing buffered
/// beyond what's being written.
class MicShare(private val session: String, private val onEnded: () -> Unit) : Share {
    @Volatile private var running = true
    private val thread = Thread(::run, "linksy-mic").apply { start() }

    @SuppressLint("MissingPermission") // Asked before the session is accepted.
    private fun run() {
        val record = open() ?: run {
            Log.w("linksy", "no microphone")
            onEnded()
            return
        }
        val chunk = ByteArray(CHUNK)
        try {
            record.startRecording()
            while (running) {
                var filled = 0
                while (running && filled < CHUNK) {
                    val n = record.read(chunk, filled, CHUNK - filled)
                    if (n <= 0) break
                    filled += n
                }
                if (!running || filled < CHUNK) break
                if (!NativeSession.write(session, chunk.copyOf())) break
            }
        } catch (e: Exception) {
            Log.w("linksy", "microphone stopped", e)
        } finally {
            runCatching { record.stop() }
            record.release()
        }
        if (running) onEnded()
    }

    /// Voice processing (echo cancellation, noise suppression) first, the
    /// plain microphone otherwise.
    @SuppressLint("MissingPermission")
    private fun open(): AudioRecord? {
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return null
        for (source in intArrayOf(MediaRecorder.AudioSource.VOICE_COMMUNICATION, MediaRecorder.AudioSource.MIC)) {
            val record = runCatching {
                AudioRecord(source, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, CHUNK * 4))
            }.getOrNull() ?: continue
            if (record.state == AudioRecord.STATE_INITIALIZED) return record
            record.release()
        }
        return null
    }

    override fun stop() {
        running = false
        thread.join(500)
    }

    companion object {
        private const val RATE = 48_000
        /// 10 ms of 16-bit mono at 48 kHz.
        private const val CHUNK = 960
    }
}
