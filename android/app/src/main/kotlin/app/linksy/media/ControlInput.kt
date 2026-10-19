package app.linksy.media

import android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK
import android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_HOME
import android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_RECENTS
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Path
import android.os.Bundle
import android.os.SystemClock
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject
import java.nio.ByteBuffer

/// Reads a `control` session's input frames (u32 big-endian length + JSON,
/// docs/protocol.md §4.8) and plays them on this phone through [ControlService].
class ControlInput(private val context: Context, private val session: String) {
    @Volatile private var running = true
    private val thread = Thread(::loop, "linksy-control").apply { start() }

    // Where the computer's pointer is, in screen pixels, and the stroke in
    // progress while the left button is down.
    private var x = 0f
    private var y = 0f
    private var stroke: MutableList<Pair<Float, Float>>? = null
    private var strokeStart = 0L

    fun stop() {
        running = false
    }

    private fun loop() {
        val pending = java.io.ByteArrayOutputStream()
        while (running) {
            val chunk = NativeSession.read(session) ?: break
            pending.write(chunk)
            var bytes = pending.toByteArray()
            var at = 0
            while (bytes.size - at >= 4) {
                val n = ByteBuffer.wrap(bytes, at, 4).int
                if (n < 0 || bytes.size - at - 4 < n) break
                val json = String(bytes, at + 4, n, Charsets.UTF_8)
                at += 4 + n
                runCatching { apply(JSONObject(json)) }.onFailure { Log.w("linksy", "bad input $json", it) }
            }
            pending.reset()
            if (at < bytes.size) pending.write(bytes, at, bytes.size - at)
        }
    }

    private fun screen(): Pair<Int, Int> {
        val m = DisplayMetrics()
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(m)
        return m.widthPixels to m.heightPixels
    }

    private fun apply(msg: JSONObject) {
        val service = ControlService.instance ?: return
        when (msg.optString("type")) {
            "pointer" -> {
                val (w, h) = screen()
                x = (msg.optDouble("x").coerceIn(0.0, 1.0) * (w - 1)).toFloat()
                y = (msg.optDouble("y").coerceIn(0.0, 1.0) * (h - 1)).toFloat()
                stroke?.add(x to y)
            }
            "button" -> {
                val pressed = msg.optBoolean("pressed")
                when (msg.optString("button")) {
                    "left" -> if (pressed) {
                        stroke = mutableListOf(x to y)
                        strokeStart = SystemClock.uptimeMillis()
                    } else {
                        stroke?.let { dispatchStroke(it, SystemClock.uptimeMillis() - strokeStart) }
                        stroke = null
                    }
                    "right", "back" -> if (pressed) service.performGlobalAction(GLOBAL_ACTION_BACK)
                    "middle" -> if (pressed) service.performGlobalAction(GLOBAL_ACTION_HOME)
                }
            }
            "scroll" -> {
                // Wheel down shows what's below: drag the content up.
                val discrete = msg.optBoolean("discrete")
                val step = if (discrete) 160f else 1f
                val dy = (msg.optDouble("dy") * step).toFloat()
                val dx = (msg.optDouble("dx") * step).toFloat()
                if (dx != 0f || dy != 0f) {
                    val (w, h) = screen()
                    val toX = (x - dx).coerceIn(0f, w - 1f)
                    val toY = (y - dy).coerceIn(0f, h - 1f)
                    dispatchStroke(listOf(x to y, toX to toY), if (discrete) 120 else 60)
                }
            }
            "key" -> if (msg.optBoolean("pressed")) key(msg.optLong("keysym"))
        }
    }

    private fun dispatchStroke(points: List<Pair<Float, Float>>, millis: Long) {
        val service = ControlService.instance ?: return
        val path = Path().apply {
            moveTo(points.first().first, points.first().second)
            points.drop(1).forEach { (px, py) -> lineTo(px, py) }
            // A tap still needs a path with some length on some phones.
            if (points.size == 1) lineTo(points[0].first + 1, points[0].second + 1)
        }
        val duration = millis.coerceIn(1, GestureDescription.getMaxGestureDuration())
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
            .build()
        service.dispatchGesture(gesture, null, null)
    }

    private fun key(keysym: Long) {
        val service = ControlService.instance ?: return
        when (keysym) {
            0xff1bL -> service.performGlobalAction(GLOBAL_ACTION_BACK) // Escape
            0xff50L, 0xffebL, 0xffecL -> service.performGlobalAction(GLOBAL_ACTION_HOME) // Home, Super
            0xff09L -> service.performGlobalAction(GLOBAL_ACTION_RECENTS) // Tab
            0xff08L -> editText { it.dropLast(1) } // BackSpace
            0xff0dL, 0xff8dL -> enter()
            else -> {
                val cp = when {
                    keysym in 0x20..0x7e -> keysym.toInt()
                    keysym and 0xff000000L == 0x01000000L -> (keysym and 0xffffffL).toInt()
                    else -> return
                }
                editText { it + String(Character.toChars(cp)) }
            }
        }
    }

    /// Types into the focused field: read its text, change it, set it back.
    private fun editText(change: (String) -> String) {
        val node = focused() ?: return
        val hint = android.os.Build.VERSION.SDK_INT >= 26 && node.isShowingHintText
        val current = if (hint) "" else node.text?.toString().orEmpty()
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, change(current))
        }
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun enter() {
        val node = focused() ?: return
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
        }
    }

    private fun focused(): AccessibilityNodeInfo? =
        ControlService.instance?.rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
}
