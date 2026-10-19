package app.linksy.media

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size

/// The phone as a webcam: the back camera at 1280×720, 30 fps, into an
/// encoder (docs/protocol.md §4.8, kind `camera`).
@SuppressLint("MissingPermission") // Dart asks for the camera before a session starts.
class CameraShare(context: Context, session: String, private val onEnded: () -> Unit) : Share {
    private val thread = HandlerThread("linksy-camera").apply { start() }
    private val handler = Handler(thread.looper)
    private val encoder: H264Encoder
    private var device: CameraDevice? = null
    private var capture: CameraCaptureSession? = null

    init {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = manager.cameraIdList.firstOrNull {
            manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } ?: manager.cameraIdList.first()
        val chars = manager.getCameraCharacteristics(id)
        val size = pickSize(chars)
        encoder = H264Encoder(size.width, size.height, bitrate = 4_000_000, fps = 30, session = session, onEnded = onEnded)
        val fps = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            ?.filter { it.upper == 30 }?.maxByOrNull { it.lower }

        manager.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                device = camera
                @Suppress("DEPRECATION")
                camera.createCaptureSession(listOf(encoder.inputSurface), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        capture = s
                        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            addTarget(encoder.inputSurface)
                            if (fps != null) set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fps)
                        }
                        runCatching { s.setRepeatingRequest(request.build(), null, handler) }
                            .onFailure { Log.w("linksy", "camera didn't start", it); onEnded() }
                    }

                    override fun onConfigureFailed(s: CameraCaptureSession) = onEnded()
                }, handler)
            }

            override fun onDisconnected(camera: CameraDevice) = onEnded()
            override fun onError(camera: CameraDevice, error: Int) = onEnded()
        }, handler)
    }

    override fun stop() {
        runCatching { capture?.close() }
        runCatching { device?.close() }
        encoder.stop()
        thread.quitSafely()
    }

    private companion object {
        /// 1280×720 when the camera offers it, else the largest 16:9 size up
        /// to 1920 wide, else 1280×720 anyway (the encoder scales).
        fun pickSize(chars: CameraCharacteristics): Size {
            val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(MediaCodec::class.java).orEmpty()
            val wanted = Size(1280, 720)
            if (sizes.contains(wanted)) return wanted
            return sizes.filter { it.width * 9 == it.height * 16 && it.width <= 1920 }
                .maxByOrNull { it.width } ?: wanted
        }
    }
}
