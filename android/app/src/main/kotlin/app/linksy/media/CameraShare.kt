package app.linksy.media

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.MeteringRectangle
import android.media.MediaCodec
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import org.json.JSONObject
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.tan

/// The phone as a webcam (docs/protocol.md §4.8, kind `camera`), with the controls of
/// a camera app: lenses (front, back, and every back camera the phone
/// exposes), zoom, torch, tap-to-focus and manual focus, exposure
/// compensation and locks, white balance, stabilization and stream quality.
///
/// Every change updates the running capture request: the stream never stops.
/// Controls come from the phone's screen ([set]) or from the computer
/// (`camera_control` messages on the session, see docs/android-app.md). [onState] hears
/// every change, for the phone's controls to follow.
@SuppressLint("MissingPermission") // Dart asks for the camera before a session starts.
class CameraShare(
    private val context: Context,
    private val session: String,
    private val onEnded: () -> Unit,
) : Share {
    private val thread = HandlerThread("linksy-camera").apply { start() }
    private val handler = Handler(thread.looper)
    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val encoder: H264Encoder
    val size: Size
    private var device: CameraDevice? = null
    private var capture: CameraCaptureSession? = null
    @Volatile private var stopped = false
    /// Turns and places the picture; the camera draws into it.
    private val renderer: GlRenderer
    /// Follows how the phone is held, for automatic rotation.
    private val orientation: android.view.OrientationEventListener
    private var held = 0

    /// What can be chosen: a lens per camera the phone exposes, by facing.
    private val lenses: List<Lens>
    private var lens: Lens
    private var chars: CameraCharacteristics

    // The controls, as the phone or the computer last set them.
    private var zoom = 1f
    private var torch = false
    private var focus = "auto" // auto (continuous), point (tapped, held), manual
    private var focusPoint: Pair<Float, Float>? = null
    private var focusDistance = 0f // 0..1 of the lens's range, manual only
    private var exposure = 0 // compensation steps
    private var exposureLock = false
    private var whiteBalance = "auto"
    private var whiteBalanceLock = false
    private var stabilization = true
    private var quality = "standard"
    private var rotationMode = "auto" // auto, or fixed: 0, 90, 180, 270
    private var fill = false

    /// Every change, as [state] JSON, on the camera thread.
    @Volatile var onState: ((JSONObject) -> Unit)? = null

    private val reader: Thread

    init {
        lenses = findLenses()
        lens = lenses.firstOrNull { it.facing == "back" && it.main } ?: lenses.first()
        chars = manager.getCameraCharacteristics(lens.id)
        size = pickSize(chars)
        encoder = H264Encoder(size.width, size.height, bitrate = bitrate(quality), fps = 30, session = session, onEnded = onEnded)
        renderer = GlRenderer(size, encoder.inputSurface, size.width, size.height)
        orientation = object : android.view.OrientationEventListener(context) {
            override fun onOrientationChanged(degrees: Int) {
                if (degrees == ORIENTATION_UNKNOWN) return
                val snapped = ((degrees + 45) / 90 * 90) % 360
                if (snapped != held) handler.post {
                    held = snapped
                    if (rotationMode == "auto") turn()
                }
            }
        }
        if (orientation.canDetectOrientation()) orientation.enable()
        turn()
        open()
        reader = Thread(::readControls, "linksy-camera-control").apply { isDaemon = true; start() }
    }

    // Lenses.

    private class Lens(val id: String, val facing: String, val equivalent: Float, val main: Boolean)

    /// Each camera the phone lists, with its field of view as a zoom factor
    /// of the main camera of the same facing (0.6× ultra-wide, 3× tele…).
    private fun findLenses(): List<Lens> {
        val all = manager.cameraIdList.mapNotNull { id ->
            val c = manager.getCameraCharacteristics(id)
            val facing = when (c.get(CameraCharacteristics.LENS_FACING)) {
                CameraCharacteristics.LENS_FACING_BACK -> "back"
                CameraCharacteristics.LENS_FACING_FRONT -> "front"
                else -> return@mapNotNull null
            }
            val sizes = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(MediaCodec::class.java).orEmpty()
            if (sizes.isEmpty()) return@mapNotNull null
            Triple(id, facing, fov(c))
        }
        return all.groupBy { it.second }.flatMap { (facing, cams) ->
            // The first one Android lists for a facing is its main camera.
            val main = cams.first()
            cams.map { (id, _, fov) ->
                val ratio = if (fov > 0 && main.third > 0) (tan(main.third / 2) / tan(fov / 2)).toFloat() else 1f
                Lens(id, facing, (ratio * 10).roundToInt() / 10f, id == main.first)
            }
        }
    }

    /// Horizontal field of view in radians, from focal length and sensor width.
    private fun fov(c: CameraCharacteristics): Double {
        val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull() ?: return 0.0
        val width = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.width ?: return 0.0
        return 2 * atan(width / (2.0 * focal))
    }

    // The camera.

    private fun open() {
        manager.openCamera(lens.id, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                if (stopped) return camera.close()
                device = camera
                configure()
            }

            // Closing it to switch reports a disconnect too: only the camera in use counts.
            override fun onDisconnected(camera: CameraDevice) {
                if (device == camera) onEnded()
            }

            override fun onError(camera: CameraDevice, error: Int) {
                if (device == camera || device == null) onEnded()
            }
        }, handler)
    }

    /// A capture session drawing into the renderer (which feeds the encoder
    /// and the phone's preview).
    private fun configure() {
        val camera = device ?: return
        runCatching { capture?.close() }
        capture = null
        val outputs = listOf(renderer.input)
        @Suppress("DEPRECATION")
        camera.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                if (stopped) return
                capture = s
                apply()
                encoder.keyframe()
            }

            override fun onConfigureFailed(s: CameraCaptureSession) {
                Log.w("linksy", "camera session didn't configure")
                onEnded()
            }
        }, handler)
    }

    /// The repeating request from the current controls.
    private fun request(trigger: Boolean = false): CaptureRequest? {
        val camera = device ?: return null
        return camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
            addTarget(renderer.input)
            chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?.filter { it.upper == 30 }?.maxByOrNull { it.lower }
                ?.let { set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }

            // Zoom: the ratio API (Android 11+, which also reaches the
            // ultra-wide on logical cameras), else a crop.
            val active = chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: Rect(0, 0, size.width, size.height)
            if (Build.VERSION.SDK_INT >= 30 && zoomRange().lower != zoomRange().upper) {
                set(CaptureRequest.CONTROL_ZOOM_RATIO, zoom)
            } else if (zoom > 1f) {
                val w = (active.width() / zoom).toInt()
                val h = (active.height() / zoom).toInt()
                set(CaptureRequest.SCALER_CROP_REGION, Rect(active.centerX() - w / 2, active.centerY() - h / 2, active.centerX() + w / 2, active.centerY() + h / 2))
            }

            // Exposure: compensation, lock, metering point; the torch needs
            // plain auto-exposure.
            set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
            set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
            set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, exposure)
            set(CaptureRequest.CONTROL_AE_LOCK, exposureLock)
            set(CaptureRequest.FLASH_MODE, if (torch && hasFlash()) CameraMetadata.FLASH_MODE_TORCH else CameraMetadata.FLASH_MODE_OFF)

            // Focus.
            // The tapped point is on the stream; the camera meters its own picture.
            val regions = focusPoint?.let { renderer.toCamera(it.first, it.second) }?.let { arrayOf(metering(it, active)) }
            when {
                focus == "manual" && manualFocus() -> {
                    set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_OFF)
                    val near = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
                    set(CaptureRequest.LENS_FOCUS_DISTANCE, focusDistance * near)
                }
                focus == "point" && regions != null && autoFocus() -> {
                    set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_AUTO)
                    if (maxRegions(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) > 0) set(CaptureRequest.CONTROL_AF_REGIONS, regions)
                    if (trigger) set(CaptureRequest.CONTROL_AF_TRIGGER, CameraMetadata.CONTROL_AF_TRIGGER_START)
                }
                autoFocus() -> set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
            }
            if (regions != null && maxRegions(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) > 0) {
                set(CaptureRequest.CONTROL_AE_REGIONS, regions)
            }

            // White balance.
            set(CaptureRequest.CONTROL_AWB_MODE, awbMode(whiteBalance))
            set(CaptureRequest.CONTROL_AWB_LOCK, whiteBalanceLock)

            // Stabilization: electronic, and optical where the lens has it.
            if (videoStabilization()) {
                set(
                    CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
                    if (stabilization) CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON else CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF,
                )
            }
            if (opticalStabilization()) {
                set(
                    CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                    if (stabilization) CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON else CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_OFF,
                )
            }
        }.build()
    }

    /// Puts the controls into effect (on the camera thread).
    private fun apply(trigger: Boolean = false) {
        val s = capture ?: return
        runCatching {
            if (trigger) request(trigger = true)?.let { s.capture(it, null, handler) }
            request()?.let { s.setRepeatingRequest(it, null, handler) }
        }.onFailure { Log.w("linksy", "camera controls not applied", it) }
        onState?.invoke(state())
    }

    /// The picture's rotation now: what the user chose, or upright for how
    /// the phone is held (the camera's own formula for photo orientation).
    private fun turn() {
        renderer.rotation = when (rotationMode) {
            "auto" -> {
                val sensor = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
                val device = if (lens.facing == "front") -held else held
                (sensor + device + 360) % 360
            }
            else -> rotationMode.toIntOrNull()?.let { ((it % 360) + 360) % 360 / 90 * 90 } ?: 0
        }
        renderer.fill = fill
    }

    /// A point of the camera's picture (0..1 across and down) as a
    /// metering area. With the zoom ratio API the coordinates are those of
    /// the zoomed picture; with a crop they're the cropped part of the sensor.
    private fun metering(point: Pair<Float, Float>, active: Rect): MeteringRectangle {
        val ratioApi = Build.VERSION.SDK_INT >= 30 && zoomRange().lower != zoomRange().upper
        val area = if (ratioApi || zoom <= 1f) Rect(0, 0, active.width(), active.height()) else {
            val w = (active.width() / zoom).toInt()
            val h = (active.height() / zoom).toInt()
            Rect(active.width() / 2 - w / 2, active.height() / 2 - h / 2, active.width() / 2 + w / 2, active.height() / 2 + h / 2)
        }
        // The stream is a 16:9 cut of the sensor's picture.
        val visibleH = min(area.height().toFloat(), area.width() * size.height / size.width.toFloat())
        val visibleW = min(area.width().toFloat(), area.height() * size.width / size.height.toFloat())
        val x = area.left + (area.width() - visibleW) / 2 + point.first * visibleW
        val y = area.top + (area.height() - visibleH) / 2 + point.second * visibleH
        val half = max(area.width(), area.height()) / 20
        return MeteringRectangle(
            Rect((x - half).toInt().coerceAtLeast(0), (y - half).toInt().coerceAtLeast(0),
                (x + half).toInt().coerceAtMost(active.width() - 1), (y + half).toInt().coerceAtMost(active.height() - 1)),
            MeteringRectangle.METERING_WEIGHT_MAX - 1,
        )
    }

    // What this camera can do.

    private fun zoomRange(): Range<Float> =
        if (Build.VERSION.SDK_INT >= 30) chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE) ?: Range(1f, maxCrop())
        else Range(1f, maxCrop())

    private fun maxCrop() = chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
    private fun hasFlash() = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
    private fun maxRegions(key: CameraCharacteristics.Key<Int>) = chars.get(key) ?: 0
    private fun afModes() = chars.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toList().orEmpty()
    private fun autoFocus() = CameraMetadata.CONTROL_AF_MODE_AUTO in afModes()
    private fun manualFocus() = (chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f) > 0f
    private fun videoStabilization() = chars.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES)
        ?.contains(CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON) == true
    private fun opticalStabilization() = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)
        ?.contains(CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON) == true

    private val awbNames = mapOf(
        "auto" to CameraMetadata.CONTROL_AWB_MODE_AUTO,
        "daylight" to CameraMetadata.CONTROL_AWB_MODE_DAYLIGHT,
        "cloudy" to CameraMetadata.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT,
        "shade" to CameraMetadata.CONTROL_AWB_MODE_SHADE,
        "incandescent" to CameraMetadata.CONTROL_AWB_MODE_INCANDESCENT,
        "fluorescent" to CameraMetadata.CONTROL_AWB_MODE_FLUORESCENT,
    )

    private fun awbModes(): List<String> {
        val have = chars.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)?.toSet().orEmpty()
        return awbNames.filterValues { it in have }.keys.toList()
    }

    private fun awbMode(name: String) = awbNames[name]?.takeIf { it in (chars.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)?.toSet().orEmpty()) }
        ?: CameraMetadata.CONTROL_AWB_MODE_AUTO

    private fun bitrate(quality: String) = when (quality) {
        "saver" -> 2_000_000
        "high" -> 8_000_000
        else -> 4_000_000
    }

    /// Zoom presets like a camera app's: the widest the camera reaches
    /// (0.6× on a logical camera with an ultra-wide), 1×, 2×, 3×, 5×, 10×
    /// within its range, and separate lenses of the same facing.
    private fun presets(): List<Float> {
        val range = zoomRange()
        val out = mutableListOf<Float>()
        if (range.lower < 0.95f) out += (range.lower * 10).roundToInt() / 10f
        out += 1f
        for (z in listOf(2f, 3f, 5f, 10f)) if (z <= range.upper + 0.01f) out += z
        return out
    }

    // Controls.

    /// The capabilities and the current controls, for the phone's screen and
    /// the computer (docs/android-app.md, `camera_state`).
    fun state(): JSONObject {
        val range = zoomRange()
        val ev = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        val step = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
        return JSONObject()
            .put("width", size.width).put("height", size.height)
            .put("facing", lens.facing)
            .put("lens", lens.id)
            .put("lenses", org.json.JSONArray().apply {
                lenses.forEach {
                    put(JSONObject().put("id", it.id).put("facing", it.facing).put("zoom", it.equivalent).put("main", it.main))
                }
            })
            .put("zoom", zoom.toDouble())
            .put("zoom_min", range.lower.toDouble()).put("zoom_max", range.upper.toDouble())
            .put("zoom_presets", org.json.JSONArray(presets().map { it.toDouble() }))
            .put("torch", torch).put("has_torch", hasFlash())
            .put("focus", focus)
            .put("focus_modes", org.json.JSONArray(buildList {
                add("auto")
                if (autoFocus() && maxRegions(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) > 0) add("point")
                if (manualFocus()) add("manual")
            }))
            .put("focus_distance", focusDistance.toDouble())
            .put("focus_point", focusPoint?.let { org.json.JSONArray(listOf(it.first.toDouble(), it.second.toDouble())) } ?: JSONObject.NULL)
            .put("exposure", exposure)
            .put("exposure_min", ev?.lower ?: 0).put("exposure_max", ev?.upper ?: 0)
            .put("exposure_step", step?.toDouble() ?: 0.0)
            .put("exposure_lock", exposureLock)
            .put("white_balance", whiteBalance)
            .put("white_balances", org.json.JSONArray(awbModes()))
            .put("white_balance_lock", whiteBalanceLock)
            .put("stabilization", stabilization)
            .put("has_stabilization", videoStabilization() || opticalStabilization())
            .put("quality", quality)
            .put("rotation", renderer.rotation)
            .put("rotation_mode", rotationMode)
            .put("fill", fill)
    }

    /// Applies any of the controls in [c] (the same names as [state]).
    fun set(c: JSONObject) = handler.post {
        if (stopped) return@post
        var reopen: Lens? = null
        var trigger = false
        if (c.has("facing")) {
            val facing = c.getString("facing")
            if (facing != lens.facing) reopen = lenses.firstOrNull { it.facing == facing && it.main } ?: lenses.firstOrNull { it.facing == facing }
        }
        if (c.has("lens")) reopen = lenses.firstOrNull { it.id == c.getString("lens") }?.takeIf { it.id != lens.id } ?: reopen
        if (c.has("zoom")) zoom = c.getDouble("zoom").toFloat()
        if (c.has("torch")) torch = c.getBoolean("torch")
        if (c.has("focus")) {
            focus = c.getString("focus")
            if (focus == "auto") focusPoint = null
        }
        if (c.has("focus_point")) {
            val p = c.optJSONArray("focus_point")
            if (p != null && p.length() == 2) {
                focusPoint = p.getDouble(0).toFloat().coerceIn(0f, 1f) to p.getDouble(1).toFloat().coerceIn(0f, 1f)
                if (!c.has("focus")) focus = "point"
                trigger = focus == "point"
            }
        }
        if (c.has("focus_distance")) focusDistance = c.getDouble("focus_distance").toFloat().coerceIn(0f, 1f)
        if (c.has("exposure")) exposure = c.getInt("exposure")
        if (c.has("exposure_lock")) exposureLock = c.getBoolean("exposure_lock")
        if (c.has("white_balance")) whiteBalance = c.getString("white_balance")
        if (c.has("white_balance_lock")) whiteBalanceLock = c.getBoolean("white_balance_lock")
        if (c.has("stabilization")) stabilization = c.getBoolean("stabilization")
        if (c.has("rotation")) {
            rotationMode = c.get("rotation").toString().let { if (it == "auto") "auto" else (it.toIntOrNull() ?: 0).let { d -> (((d % 360) + 360) % 360 / 90 * 90).toString() } }
        }
        if (c.has("fill")) fill = c.getBoolean("fill")
        if (c.has("quality")) {
            quality = c.getString("quality")
            encoder.setBitrate(bitrate(quality))
        }
        turn()
        if (reopen != null) {
            switchTo(reopen)
        } else {
            clamp()
            apply(trigger)
        }
    }

    /// Front ↔ back, same stream. False when there's no other camera.
    fun switch(): Boolean {
        val other = if (lens.facing == "back") "front" else "back"
        if (lenses.none { it.facing == other }) return false
        set(JSONObject().put("facing", other))
        return true
    }

    private fun switchTo(next: Lens) {
        runCatching { capture?.close() }
        runCatching { device?.close() }
        capture = null
        device = null
        lens = next
        chars = manager.getCameraCharacteristics(next.id)
        // What the new camera can't do goes back to its default.
        zoom = 1f
        focus = "auto"
        focusPoint = null
        exposure = 0
        if (!hasFlash()) torch = false
        clamp()
        turn()
        open()
    }

    private fun clamp() {
        val range = zoomRange()
        zoom = zoom.coerceIn(range.lower, range.upper)
        val ev = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        if (ev != null) exposure = exposure.coerceIn(ev.lower, ev.upper)
        if (focus == "manual" && !manualFocus()) focus = "auto"
        if (whiteBalance !in awbModes()) whiteBalance = "auto"
    }

    /// Shows the stream on the phone too ([surface] null: stops showing it).
    fun setPreview(surface: Surface?) {
        if (!stopped) renderer.setPreview(surface)
    }

    /// `camera_control` from the computer: framed JSON (u32 big-endian length
    /// + body) on the session's stream, the same keys as [set].
    private fun readControls() {
        var pending = ByteArray(0)
        while (!stopped) {
            val chunk = NativeSession.read(session) ?: return
            pending += chunk
            while (pending.size >= 4) {
                val len = ((pending[0].toInt() and 0xff) shl 24) or ((pending[1].toInt() and 0xff) shl 16) or
                    ((pending[2].toInt() and 0xff) shl 8) or (pending[3].toInt() and 0xff)
                if (len < 0 || len > 64 * 1024) return
                if (pending.size < 4 + len) break
                val body = String(pending, 4, len, Charsets.UTF_8)
                pending = pending.copyOfRange(4 + len, pending.size)
                runCatching { JSONObject(body) }.getOrNull()
                    ?.takeIf { it.optString("type") == "camera_control" }
                    ?.let { set(it) }
            }
        }
    }

    override fun stop() {
        stopped = true
        orientation.disable()
        handler.post {
            runCatching { capture?.close() }
            runCatching { device?.close() }
        }
        renderer.stop()
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
