package org.kde.connectify.input

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import org.json.JSONObject
import org.kde.connectify.media.NativeSession

/// Injects taps, swipes, key events and text into the app that has focus,
/// driven by the computer's `ControlMsg` frames (docs/protocol.md §4.8).
///
/// Enabled by the user in Settings → Accessibility → "KDE Connectify" once,
/// then this service can synthesize input across every app - the same
/// mechanism scrcpy's ADB path gives, but from inside this app, no USB
/// debugging, no developer options.
///
/// A `control` session's reader thread (see [ShareService]) calls
/// [processFrame] with the session id; frames arrive pre-parsed by the
/// desktop-side protocol, so each `msg` here is one input event.
class ActiveInputService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        _instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We only synthesize; no event filtering needed.
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        _instance = null
        super.onDestroy()
    }

    /**
     * Handle one `ControlMsg` frame. `msg` is the JSON body of the frame
     * (u32-len + JSON, docs/protocol.md §4.8), keys as in the `input`
     * remote: `pointer` {x,y 0..1}, `swipe` {x0,y0,x1,y1,duration},
     * `key` {keycode,pressed,repeat}, `text` {text}.
     */
    fun processFrame(msg: JSONObject) {
        when (msg.optString("type")) {
            "pointer" -> {
                val (px, py) = toPixels(msg.optDouble("x"), msg.optDouble("y"))
                swipe(px, py, px, py, 60L)
            }
            "swipe" -> {
                val (ax, ay) = toPixels(msg.optDouble("x0"), msg.optDouble("y0"))
                val (bx, by) = toPixels(msg.optDouble("x1"), msg.optDouble("y1"))
                swipe(ax, ay, bx, by, msg.optLong("duration", 200L))
            }
            "key" -> {
                val code = msg.optInt("keycode")
                if (code != 0) key(code)
            }
            "text" -> type(msg.optString("text", ""))
            else -> {}
        }
    }

    private fun toPixels(nx: Double, ny: Double): Pair<Int, Int> {
        val dm: DisplayMetrics = resources.displayMetrics
        val x = (nx.coerceIn(0.0, 1.0) * dm.widthPixels).toInt()
        val y = (ny.coerceIn(0.0, 1.0) * dm.heightPixels).toInt()
        return Pair(x, y)
    }

    private fun swipe(x0: Int, y0: Int, x1: Int, y1: Int, durationMs: Long) {
        val path = Path()
        path.moveTo(x0.toFloat(), y0.toFloat())
        path.lineTo(x1.toFloat(), y1.toFloat())
        val gesture = GestureDescription.Builder()
            .addStroke(
                GestureDescription.StrokeDescription(path, 0L, durationMs.coerceIn(50L, 5000L)),
            )
            .build()
        dispatchGesture(gesture, null, null)
    }

    /// `input keyevent` code (see §4.8's keysym table) via global actions;
    /// arbitrary keycodes have no public accessibility dispatch, so they are
    /// no-ops until an IME path is added.
    private fun key(code: Int) {
        when (code) {
            4 -> performGlobalAction(GLOBAL_ACTION_BACK)
            3 -> performGlobalAction(GLOBAL_ACTION_HOME)
            82 -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            26 -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            }
            else -> {}
        }
    }

    private fun type(text: String) {
        if (text.isEmpty()) return
        val root = rootInActiveWindow ?: return
        root.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,
            Bundle().apply { putCharSequence(CHARACTER_SEQ, text) })
    }

    companion object {
        private const val CHARACTER_SEQ = "android.accessibilityservice.SpeechRecognizerController"
        @Volatile
        var _instance: ActiveInputService? = null
            private set
    }
}
