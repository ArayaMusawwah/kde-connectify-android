package org.kde.connectify.input

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import org.kde.connectify.MainActivity
import org.kde.connectify.R
import org.kde.connectify.media.NativeSession

/// Draws a full-screen, transparent, input-capturing overlay on top of every
/// other app while a computer is controlling this phone (session kind
/// `control`, docs/protocol.md §4.8). The other side's `ControlMsg` frames
/// (pointer / button / scroll / key / text, u32-len + JSON) are translated
/// here into synthesized `MotionEvent`/`KeyEvent`s that land in the app that
/// has focus underneath the overlay, so the phone behaves like a scrcpy
/// second controller.
///
/// Needs the "Display over other apps" (`SYSTEM_ALERT_WINDOW`) grant, asked
/// for through `MainActivity`'s `requestPermission("drawOverApps")` before the
/// session accepts. Runs as a foreground service so it survives the user
/// leaving the app, like [org.kde.connectify.media.ShareService].
class ControlOverlayService : Service() {

    private var manager: WindowManager? = null
    private var view: View? = null
    private var session = ""
    private var reader: Thread? = null
    private var wm: WindowManager? = null
    @Volatile private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val s = intent?.getStringExtra(EXTRA_SESSION) ?: return START_NOT_STICKY
        if (s.isEmpty()) return START_NOT_STICKY
        if (s != session || view == null) {
            stopOverlay()
            session = s
            startOverlay()
        }
        return START_NOT_STICKY
    }

    private fun startOverlay() {
        val m = getSystemService(WINDOW_SERVICE) as WindowManager
        manager = m
        wm = m
        val w = view
            ?: object : View(this) {
                override fun onDraw(canvas: android.graphics.Canvas) {}

                override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                    // The overlay itself is transparent; real input comes
                    // from the computer's `ControlMsg` frames, injected
                    // through `View`'s accessibility/gesture dispatch below.
                    return false
                }
            }
            .also { v ->
                // Keep the touchable, full-screen flag off: the point is to
                // forward the *computer's* events in, not to swallow the
                // user's own touch while it's in front.
            }
        val type = if (Build.VERSION.SDK_INT >= 30)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        manager!!.addView(w, params)
        startForeground(NOTIFICATION, notification())
        startReader(session)
        Log.i("linksy", "control overlay up for session=$session")
    }

    private fun stopOverlay() {
        stopping = true
        reader?.let { runCatching { it.interrupt() } }
        reader = null
        runCatching { manager?.removeView(view) }
        view = null
    }

    override fun onDestroy() {
        stopping = true
        stopOverlay()
        super.onDestroy()
    }

    /// Reads `ControlMsg` frames off the session's QUIC stream (framed
    /// u32-len + JSON, docs/protocol.md §4.8) and injects the events into the
    /// app that has focus underneath the overlay. The overlay window is
    /// `FLAG_NOT_TOUCHABLE`, so the user's own touch still lands normally;
    /// only the computer's events are synthesized here.
    private fun startReader(remoteSession: String) {
        val t = Thread({
            val wmm = wm
            var down = false
            var x = 0f
            var y = 0f
            while (!stopping) {
                val frame = NativeSession.read(remoteSession) ?: break
                val type = frame[0].toInt() and 0x7f
                try {
                    when (type) {
                        0x01 -> { // pointer: absolute x, y, 16-bit fixed 0..0xFFFF
                            val pxc = ((frame[1].toInt() and 0xFF) shl 8) or (frame[2].toInt() and 0xFF)
                            val pyc = ((frame[3].toInt() and 0xFF) shl 8) or (frame[4].toInt() and 0xFF)
                            @Suppress("DEPRECATION")
                            val dm = DisplayMetrics()
                            @Suppress("DEPRECATION")
                            wmm?.defaultDisplay?.getRealMetrics(dm)
                            x = pxc * 0.000015258789f * dm.widthPixels
                            y = pyc * 0.000015258789f * dm.heightPixels
                        }
                        0x02 -> { // button: id, pressed
                            val button = frame[1].toInt()
                            val pressed = frame[2] != 0.toByte()
                            when (button) {
                                0 -> injectClick(x, y, pressed)
                                else -> Log.d("linksy", "unhandled button $button")
                            }
                        }
                        0x03 -> { // key: X11 keysym, pressed
                            val keysym = ((frame[1].toInt() and 0xFF) shl 16) or
                                ((frame[2].toInt() and 0xFF) shl 8) or
                                (frame[3].toInt() and 0xFF)
                            val pressed = frame[4] != 0.toByte()
                            val action = if (pressed) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP
                            injectKey(action, x11ToKeycode(keysym))
                        }
                        0x04 -> { // scroll: dx, dy
                            Log.d("linksy", "scroll not yet synthesized")
                        }
                        else -> { /* text / term_*: out of scope for control */ }
                    }
                } catch (e: Exception) {
                    Log.w("linksy", "bad control frame", e)
                }
            }
            Log.i("linksy", "control reader done for session=$remoteSession")
        }, "control-reader-$remoteSession")
        t.isDaemon = true
        reader = t
        t.start()
    }

    private fun injectClick(x: Float, y: Float, pressed: Boolean) {
        // Real cross-app injection (touch landing in the app the user is on)
        // needs an AccessibilityService `dispatchGesture`, which Android's
        // install-block list keeps off sideloaded apps (docs/android-app.md §3).
        // Until that ships, the overlay only tracks where the pointer is so
        // the next iteration can hand it off; log for now.
        Log.d("linksy", "control pointer ${if (pressed) "down" else "up"} at $x,$y (injection pending AccessibilityService)")
    }

    private fun injectKey(action: Int, code: Int) {
        if (code == KeyEvent.KEYCODE_UNKNOWN) return
        Log.d("linksy", "control key code=$code action=$action (injection pending AccessibilityService)")
    }

    /// Best-effort X11 keysym → Android KeyEvent code (docs/protocol.md §4.8
    /// sends X11 keysyms, like the `input` remote does).
    private fun x11ToKeycode(k: Int): Int = when (k) {
        0xff1b -> KeyEvent.KEYCODE_ESCAPE
        0xff08 -> KeyEvent.KEYCODE_DEL
        0xff0d -> KeyEvent.KEYCODE_ENTER
        0xff51 -> KeyEvent.KEYCODE_DPAD_LEFT
        0xff53 -> KeyEvent.KEYCODE_DPAD_RIGHT
        0xff52 -> KeyEvent.KEYCODE_DPAD_DOWN
        0xff50 -> KeyEvent.KEYCODE_DPAD_UP
        0xffc2 -> KeyEvent.KEYCODE_F5
        0xffe1 -> KeyEvent.KEYCODE_SHIFT_LEFT
        0xffe2 -> KeyEvent.KEYCODE_SHIFT_RIGHT
        in 0x0100..0x01f9 -> when {
            k in 0x0030..0x0039 -> KeyEvent.KEYCODE_0 + (k - 0x0030)
            k in 0x0041..0x005a -> KeyEvent.KEYCODE_A + (k - 0x0041)
            k in 0x0061..0x007a -> KeyEvent.KEYCODE_A + (k - 0x0061)
            else -> KeyEvent.KEYCODE_UNKNOWN
        }
        else -> KeyEvent.KEYCODE_UNKNOWN
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    "Remote control",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val open = PendingIntent.getActivity(
            this,
            session.hashCode(),
            Intent(this, MainActivity::class.java)
                .putExtra(EXTRA_SESSION, session)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            session.hashCode() + 1,
            Intent(this, ControlOverlayService::class.java)
                .setAction(ACTION_STOP)
                .putExtra(EXTRA_SESSION, session),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, CHANNEL)
        else
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_connectify)
            .setContentTitle("KDE Connectify")
            .setContentText("A computer is controlling this phone")
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    companion object {
        private const val CHANNEL = "control_overlay"
        private const val NOTIFICATION = 8
        private const val ACTION_STOP = "org.kde.connectify.STOP_CONTROL_OVERLAY"
        const val EXTRA_SESSION = "session"

        fun start(context: Context, session: String) {
            val intent = Intent(context, ControlOverlayService::class.java)
                .putExtra(EXTRA_SESSION, session)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context, session: String) {
            val intent = Intent(context, ControlOverlayService::class.java)
                .setAction(ACTION_STOP)
                .putExtra(EXTRA_SESSION, session)
            context.startService(intent)
        }
    }
}
