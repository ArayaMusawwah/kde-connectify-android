package app.linksy.media

import android.media.MediaCodec
import android.media.MediaCodecInfo.CodecCapabilities
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.view.Surface

/// Hardware H.264 the way linksy-desktop decodes it (docs/protocol.md §4.8): Annex-B,
/// Constrained Baseline, a keyframe at least every 2 s, SPS/PPS before every
/// keyframe. Frames come in through [inputSurface]; each encoded unit goes to
/// the session. [onEnded] runs once if the session goes away.
class H264Encoder(
    width: Int,
    height: Int,
    bitrate: Int,
    fps: Int,
    private val session: String,
    private val onEnded: () -> Unit,
) {
    private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    val inputSurface: Surface
    @Volatile private var running = true
    private val drain: Thread

    init {
        configure(width, height, bitrate, fps)
        inputSurface = codec.createInputSurface()
        codec.start()
        drain = Thread(::drainLoop, "linksy-encoder").apply { start() }
    }

    private fun configure(width: Int, height: Int, bitrate: Int, fps: Int) {
        fun format(profile: Int) = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_PROFILE, profile)
            // A still screen produces no frames; repeat the last one so the
            // viewer keeps getting pictures (and keyframes).
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)
            // Screens refresh at 60 Hz or more; the desktop expects up to 30.
            if (Build.VERSION.SDK_INT >= 29) setFloat(MediaFormat.KEY_MAX_FPS_TO_ENCODER, fps.toFloat())
        }
        val profiles = buildList {
            if (Build.VERSION.SDK_INT >= 27) add(CodecProfileLevel.AVCProfileConstrainedBaseline)
            add(CodecProfileLevel.AVCProfileBaseline)
        }
        for ((i, profile) in profiles.withIndex()) {
            try {
                codec.configure(format(profile), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                return
            } catch (e: Exception) {
                if (i == profiles.lastIndex) throw e
                Log.w(TAG, "profile $profile not supported, trying the next", e)
                codec.reset()
            }
        }
    }

    private fun drainLoop() {
        val info = MediaCodec.BufferInfo()
        var config = ByteArray(0)
        try {
            while (running) {
                val index = codec.dequeueOutputBuffer(info, 10_000)
                if (index < 0) continue
                val buffer = codec.getOutputBuffer(index)
                val bytes = ByteArray(info.size)
                buffer?.position(info.offset)
                buffer?.get(bytes, 0, info.size)
                codec.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    config = bytes
                    continue
                }
                val key = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                val out = if (key && config.isNotEmpty() && !startsWithSps(bytes)) config + bytes else bytes
                if (out.isNotEmpty() && !NativeSession.write(session, out)) {
                    running = false
                    onEnded()
                }
            }
        } catch (e: Exception) {
            if (running) {
                Log.w(TAG, "encoder stopped", e)
                running = false
                onEnded()
            }
        }
    }

    /// A keyframe now (the picture changed completely: another camera).
    fun keyframe() {
        runCatching {
            codec.setParameters(android.os.Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        }
    }

    fun stop() {
        running = false
        drain.join(500)
        runCatching { codec.stop() }
        runCatching { codec.release() }
        inputSurface.release()
    }

    companion object {
        private const val TAG = "linksy"

        /// What the phone's default H.264 encoder can do, for picking sizes.
        fun capabilities(): android.media.MediaCodecInfo.VideoCapabilities? = runCatching {
            val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            try {
                codec.codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities
            } finally {
                codec.release()
            }
        }.getOrNull()

        /// Whether the encoder already put SPS (NAL type 7) in front.
        private fun startsWithSps(b: ByteArray): Boolean {
            val start = when {
                b.size > 4 && b[0].toInt() == 0 && b[1].toInt() == 0 && b[2].toInt() == 0 && b[3].toInt() == 1 -> 4
                b.size > 3 && b[0].toInt() == 0 && b[1].toInt() == 0 && b[2].toInt() == 1 -> 3
                else -> return false
            }
            return b[start].toInt() and 0x1f == 7
        }
    }
}
