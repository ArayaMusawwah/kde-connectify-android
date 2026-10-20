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
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080).apply {
            // A keyframe of a busy desktop is big; make sure one always fits.
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 2 * 1024 * 1024)
        }
        decoder.configure(format, producer.surface, null, 0)
        decoder.start()
        input = Thread(::readLoop, "linksy-display-in").apply { start() }
        output = Thread(::renderLoop, "linksy-display-out").apply { start() }
    }

    private fun readLoop() {
        val nals = AnnexB()
        val units = AccessUnits(::queue)
        try {
            while (running) {
                val chunk = NativeSession.read(session) ?: break
                nals.push(chunk, units::push)
            }
        } catch (e: Exception) {
            if (running) Log.w("linksy", "display stream stopped", e)
        }
        if (running) onEnded()
    }

    /// One whole picture (or SPS+PPS, as codec config) per input buffer, with
    /// one timestamp: a decoder fed slice by slice never sees a full frame.
    private fun queue(unit: ByteArray, config: Boolean) {
        val flags = if (config) MediaCodec.BUFFER_FLAG_CODEC_CONFIG else 0
        while (running) {
            val index = decoder.dequeueInputBuffer(10_000)
            if (index < 0) continue
            val buffer = decoder.getInputBuffer(index) ?: return
            if (unit.size > buffer.capacity()) {
                Log.w("linksy", "display frame of ${unit.size} bytes doesn't fit, skipped")
                decoder.queueInputBuffer(index, 0, 0, System.nanoTime() / 1000, 0)
                return
            }
            buffer.clear()
            buffer.put(unit)
            decoder.queueInputBuffer(index, 0, unit.size, System.nanoTime() / 1000, flags)
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

    /// Groups NAL units into access units (docs/protocol.md §7): a new picture starts
    /// at an access unit delimiter (type 9, which the desktop sends before each
    /// frame), at SEI/SPS/PPS after a slice, or at a slice whose
    /// first_mb_in_slice is 0. SPS and PPS go out together as codec config,
    /// again only when they change.
    private class AccessUnits(private val emit: (ByteArray, Boolean) -> Unit) {
        private val unit = java.io.ByteArrayOutputStream()
        private var hasPicture = false
        private val config = java.io.ByteArrayOutputStream()
        private var sentConfig = ByteArray(0)

        fun push(nal: ByteArray) {
            val header = if (nal.size > 3 && nal[2].toInt() == 1) 3 else 4
            if (nal.size <= header) return
            when (val type = nal[header].toInt() and 0x1f) {
                7, 8 -> {
                    flush()
                    if (type == 7) config.reset()
                    config.write(nal)
                }
                1, 5 -> {
                    val firstSlice = nal.size > header + 1 && (nal[header + 1].toInt() and 0x80) != 0
                    if (hasPicture && firstSlice) flush()
                    sendConfig()
                    unit.write(nal)
                    hasPicture = true
                }
                6, 9, in 14..18 -> {
                    if (hasPicture) flush()
                    unit.write(nal)
                }
                else -> unit.write(nal)
            }
        }

        private fun sendConfig() {
            if (config.size() == 0) return
            val bytes = config.toByteArray()
            config.reset()
            if (!bytes.contentEquals(sentConfig)) {
                sentConfig = bytes
                emit(bytes, true)
            }
        }

        private fun flush() {
            // Before the first slice, keep what leads the picture (AUD, SEI).
            if (!hasPicture) return
            emit(unit.toByteArray(), false)
            unit.reset()
            hasPicture = false
        }
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
