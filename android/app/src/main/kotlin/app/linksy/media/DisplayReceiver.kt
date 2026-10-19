package app.linksy.media

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import io.flutter.view.TextureRegistry

/// This phone as a computer's second display (docs/protocol.md §4.8, kind
/// `display`): decodes the computer's H.264 (Annex-B, no framing) into a
/// Flutter texture. Input goes back separately, from Dart.
class DisplayReceiver(
    private val session: String,
    private val producer: TextureRegistry.SurfaceProducer,
    private val onSize: (Int, Int) -> Unit,
    private val onEnded: () -> Unit,
) {
    private val decoder = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    @Volatile private var running = true
    private val input: Thread
    private val output: Thread

    init {
        // The desktop sends 1920×1080 today; the decoder adapts to the stream.
        producer.setSize(1920, 1080)
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            // The texture gets a new surface when the app comes back.
            override fun onSurfaceAvailable() {
                runCatching { decoder.setOutputSurface(producer.surface) }
            }
        })
        decoder.configure(
            MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080),
            producer.surface, null, 0,
        )
        decoder.start()
        input = Thread(::readLoop, "linksy-display-in").apply { start() }
        output = Thread(::renderLoop, "linksy-display-out").apply { start() }
    }

    private fun readLoop() {
        val nals = AnnexB()
        try {
            while (running) {
                val chunk = NativeSession.read(session) ?: break
                nals.push(chunk) { nal -> queue(nal) }
            }
        } catch (e: Exception) {
            if (running) Log.w("linksy", "display stream stopped", e)
        }
        if (running) onEnded()
    }

    private fun queue(nal: ByteArray) {
        if (nal.size < 5) return
        val type = nal[if (nal[2].toInt() == 1) 3 else 4].toInt() and 0x1f
        val flags = if (type == 7 || type == 8) MediaCodec.BUFFER_FLAG_CODEC_CONFIG else 0
        while (running) {
            val index = decoder.dequeueInputBuffer(10_000)
            if (index < 0) continue
            decoder.getInputBuffer(index)?.apply { clear(); put(nal) }
            decoder.queueInputBuffer(index, 0, nal.size, System.nanoTime() / 1000, flags)
            return
        }
    }

    private fun renderLoop() {
        val info = MediaCodec.BufferInfo()
        try {
            while (running) {
                when (val index = decoder.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = decoder.outputFormat
                        val w = if (f.containsKey("crop-right")) f.getInteger("crop-right") - f.getInteger("crop-left") + 1
                        else f.getInteger(MediaFormat.KEY_WIDTH)
                        val h = if (f.containsKey("crop-bottom")) f.getInteger("crop-bottom") - f.getInteger("crop-top") + 1
                        else f.getInteger(MediaFormat.KEY_HEIGHT)
                        producer.setSize(w, h)
                        onSize(w, h)
                    }
                    in 0..Int.MAX_VALUE -> decoder.releaseOutputBuffer(index, true)
                }
            }
        } catch (e: Exception) {
            if (running) Log.w("linksy", "display decoder stopped", e)
        }
    }

    fun stop() {
        running = false
        NativeSession.finish(session)
        input.join(300)
        output.join(300)
        runCatching { decoder.stop() }
        runCatching { decoder.release() }
        producer.release()
    }

    /// Splits an Annex-B byte stream into NAL units (each with its start
    /// code), across chunk boundaries.
    private class AnnexB {
        private var buf = ByteArray(0)

        fun push(chunk: ByteArray, emit: (ByteArray) -> Unit) {
            buf += chunk
            var start = next(0) ?: run { return }
            while (true) {
                val end = next(start + 3) ?: break
                emit(buf.copyOfRange(start, end))
                start = end
            }
            buf = buf.copyOfRange(start, buf.size)
        }

        /// Index of the next start code (00 00 01, or 00 00 00 01) from [from].
        private fun next(from: Int): Int? {
            var i = from
            while (i + 3 <= buf.size) {
                if (buf[i].toInt() == 0 && buf[i + 1].toInt() == 0) {
                    if (buf[i + 2].toInt() == 1) return if (i > 0 && buf[i - 1].toInt() == 0 && i - 1 >= from) i - 1 else i
                    if (i + 4 <= buf.size && buf[i + 2].toInt() == 0 && buf[i + 3].toInt() == 1) return i
                }
                i++
            }
            return null
        }
    }
}
