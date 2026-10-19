package app.linksy.media

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import kotlin.math.max
import kotlin.math.min

/// The phone's screen, mirrored into an encoder. Scaled to fit 1920×1080
/// (either way round), which every phone encoder handles.
class ScreenShare(
    context: Context,
    private val projection: MediaProjection,
    session: String,
    onEnded: () -> Unit,
) : Share {
    private val encoder: H264Encoder
    private val display: VirtualDisplay

    init {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        val (w, h) = fit(metrics.widthPixels, metrics.heightPixels)
        encoder = H264Encoder(w, h, bitrate = 6_000_000, fps = 30, session = session, onEnded = onEnded)
        // Android 14 wants this before the virtual display exists.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() = onEnded()
        }, Handler(Looper.getMainLooper()))
        display = projection.createVirtualDisplay(
            "linksy", w, h, metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, encoder.inputSurface, null, null,
        ) ?: error("screen capture gave no display")
    }

    override fun stop() {
        display.release()
        encoder.stop()
        projection.stop()
    }

    private companion object {
        /// Fits within 1920×1080 keeping the aspect, in multiples of 16.
        fun fit(width: Int, height: Int): Pair<Int, Int> {
            val long = max(width, height).toDouble()
            val short = min(width, height).toDouble()
            val scale = min(1.0, min(1920 / long, 1080 / short))
            fun round(v: Double) = max(16, (v * scale).toInt() / 16 * 16)
            return round(width.toDouble()) to round(height.toDouble())
        }
    }
}

/// Something being shared into a session.
interface Share {
    fun stop()
}
