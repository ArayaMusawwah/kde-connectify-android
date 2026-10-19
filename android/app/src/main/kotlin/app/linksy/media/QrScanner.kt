package app.linksy.media

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import io.flutter.view.TextureRegistry

/// The pairing QR scanner: the back camera previewed into a Flutter texture,
/// frames decoded on the phone with ZXing. Offline, no Google services.
@SuppressLint("MissingPermission") // Dart asks for the camera first.
class QrScanner(
    context: Context,
    private val producer: TextureRegistry.SurfaceProducer,
    private val onCode: (String) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val thread = HandlerThread("linksy-scanner").apply { start() }
    private val handler = Handler(thread.looper)
    private val analysis = HandlerThread("linksy-qr").apply { start() }
    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val cameraId = manager.cameraIdList.firstOrNull {
        manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
    } ?: manager.cameraIdList.first()
    private val chars = manager.getCameraCharacteristics(cameraId)
    val size: Size = pickSize()
    /// How far the camera's picture is turned from the phone held upright.
    val rotation: Int = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
    private val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
    private val qr = QRCodeReader()
    private val hints = mapOf(
        DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
        DecodeHintType.TRY_HARDER to true,
    )
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    @Volatile private var torch = false
    @Volatile private var stopped = false

    init {
        producer.setSize(size.width, size.height)
        reader.setOnImageAvailableListener({ r -> decode(r) }, Handler(analysis.looper))
        manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                if (stopped) return camera.close()
                device = camera
                @Suppress("DEPRECATION")
                camera.createCaptureSession(
                    listOf(producer.surface, reader.surface),
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            session = s
                            repeat()
                        }

                        override fun onConfigureFailed(s: CameraCaptureSession) = onError("The camera didn't start.")
                    },
                    handler,
                )
            }

            override fun onDisconnected(camera: CameraDevice) = camera.close()
            override fun onError(camera: CameraDevice, error: Int) {
                camera.close()
                onError("The camera isn't available.")
            }
        }, handler)
    }

    private fun repeat() {
        val camera = device ?: return
        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
            addTarget(producer.surface)
            addTarget(reader.surface)
            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            set(CaptureRequest.FLASH_MODE, if (torch) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF)
        }
        runCatching { session?.setRepeatingRequest(request.build(), null, handler) }
    }

    fun setTorch(on: Boolean) {
        torch = on
        handler.post(::repeat)
    }

    /// The luminance plane is all a QR code needs.
    private fun decode(r: ImageReader) {
        val image = r.acquireLatestImage() ?: return
        try {
            if (stopped) return
            val plane = image.planes[0]
            val w = image.width
            val h = image.height
            val data = ByteArray(w * h)
            val buf = plane.buffer
            for (row in 0 until h) {
                buf.position(row * plane.rowStride)
                buf.get(data, row * w, w)
            }
            val source = PlanarYUVLuminanceSource(data, w, h, 0, 0, w, h, false)
            val text = qr.decode(BinaryBitmap(HybridBinarizer(source)), hints).text
            onCode(text)
        } catch (_: NotFoundException) {
            // No code in this frame.
        } catch (_: Exception) {
            // A damaged or partial code; the next frame tries again.
        } finally {
            qr.reset()
            image.close()
        }
    }

    fun stop() {
        stopped = true
        runCatching { session?.close() }
        runCatching { device?.close() }
        reader.close()
        thread.quitSafely()
        analysis.quitSafely()
        producer.release()
    }

    /// Close to 1280×720: sharp enough to read a code across a desk, light
    /// enough to decode every frame.
    private fun pickSize(): Size {
        val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(ImageFormat.YUV_420_888).orEmpty()
        return sizes.minByOrNull { kotlin.math.abs(it.width * it.height - 1280 * 720) } ?: Size(1280, 720)
    }
}
