package app.linksy

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import app.linksy.media.ControlService
import app.linksy.media.DisplayReceiver
import app.linksy.media.NativeSession
import app.linksy.media.ShareService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    /// A `linksy://pair?…` link that opened the app, until Dart asks for it.
    private var pendingLink: String? = null

    /// Waiting on the system's screen capture prompt: the session and Dart's reply.
    private var pendingCapture: Pair<String, MethodChannel.Result>? = null
    /// Dart's replies waiting on Android's permission dialogs, by request code.
    private val pendingPermissions = mutableMapOf<Int, MethodChannel.Result>()

    private var engine: FlutterEngine? = null
    /// Second-display sessions on screen, by session.
    private val displays = mutableMapOf<String, DisplayReceiver>()
    /// Display input goes out in order, off the UI thread (writes can wait).
    private val inputWriter = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engine = flutterEngine
        pendingLink = linkFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.linksy/platform").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceName" -> result.success(deviceName())
                    "takeLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    "requestScreenCapture" -> requestScreenCapture(call.argument<String>("session")!!, result)
                    "requestCamera" -> requestPermission(Manifest.permission.CAMERA, REQUEST_CAMERA, result)
                    "requestPermission" -> when (call.argument<String>("name")) {
                        "camera" -> requestPermission(Manifest.permission.CAMERA, REQUEST_CAMERA, result)
                        "notifications" -> if (Build.VERSION.SDK_INT >= 33) {
                            requestPermission(Manifest.permission.POST_NOTIFICATIONS, REQUEST_NOTIFICATIONS, result)
                        } else {
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                    "permissions" -> result.success(
                        mapOf(
                            "notifications" to (Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)),
                            "camera" to granted(Manifest.permission.CAMERA),
                            "control" to ControlService.enabled(this@MainActivity),
                        ),
                    )
                    "startShare" -> {
                        ShareService.start(
                            this@MainActivity,
                            call.argument<String>("session")!!,
                            call.argument<String>("kind")!!,
                            call.argument<String>("peer") ?: "Your computer",
                        )
                        result.success(null)
                    }
                    "controlEnabled" -> result.success(ControlService.enabled(this@MainActivity))
                    "openAccessibilitySettings" -> {
                        openControlSettings()
                        result.success(null)
                    }
                    "startDisplay" -> result.success(startDisplay(call.argument<String>("session")!!))
                    "stopDisplay" -> {
                        displays.remove(call.argument<String>("session")!!)?.stop()
                        result.success(null)
                    }
                    "displayInput" -> {
                        val session = call.argument<String>("session")!!
                        val frames = call.argument<ByteArray>("frames")!!
                        inputWriter.execute { NativeSession.write(session, frames) }
                        result.success(null)
                    }
                    "stopShare" -> {
                        ShareService.stop(this@MainActivity, call.argument<String>("session")!!)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = linkFrom(intent) ?: return
        channel?.invokeMethod("link", link) ?: run { pendingLink = link }
    }

    // mDNS presence needs multicast, which Android filters out unless an app
    // holds a lock. Hold it only while the app is on screen.
    override fun onStart() {
        super.onStart()
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifi.createMulticastLock("linksy").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onStop() {
        multicastLock?.takeIf { it.isHeld }?.release()
        multicastLock = null
        super.onStop()
    }

    /// Decodes a second-display session into a new Flutter texture; returns
    /// its id for Dart's `Texture` widget.
    private fun startDisplay(session: String): Long? {
        val producer = engine?.renderer?.createSurfaceProducer() ?: return null
        displays[session] = DisplayReceiver(
            session, producer,
            onSize = { w, h ->
                runOnUiThread { channel?.invokeMethod("displaySize", mapOf("session" to session, "width" to w, "height" to h)) }
            },
            onEnded = { runOnUiThread { channel?.invokeMethod("displayEnded", session) } },
        )
        return producer.id()
    }

    override fun onDestroy() {
        displays.values.forEach { it.stop() }
        displays.clear()
        inputWriter.shutdown()
        super.onDestroy()
    }

    /// Android's own "start recording or casting?" prompt. The consent is kept
    /// for the session until the share service starts.
    private fun requestScreenCapture(session: String, result: MethodChannel.Result) {
        askNotifications()
        pendingCapture?.second?.success(false)
        pendingCapture = session to result
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CAPTURE)
    }

    private fun granted(permission: String) =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /// Android's own permission dialog. Once the user has refused and Android
    /// stops showing it, opens Linksy's app settings instead, where it can
    /// still be turned on. Replies true only if granted now.
    private fun requestPermission(permission: String, code: Int, result: MethodChannel.Result) {
        if (granted(permission)) {
            result.success(true)
            return
        }
        val prefs = getSharedPreferences("permissions", MODE_PRIVATE)
        if (prefs.getBoolean(permission, false) && !shouldShowRequestPermissionRationale(permission)) {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", packageName, null)),
            )
            result.success(false)
            return
        }
        prefs.edit().putBoolean(permission, true).apply()
        pendingPermissions.remove(code)?.success(false)
        pendingPermissions[code] = result
        requestPermissions(arrayOf(permission), code)
    }

    /// The sharing notification (and its Stop button) needs this on Android
    /// 13+; asked in passing, without waiting for the answer.
    private fun askNotifications() {
        if (Build.VERSION.SDK_INT >= 33 && !granted(Manifest.permission.POST_NOTIFICATIONS) &&
            !pendingPermissions.containsKey(REQUEST_NOTIFICATIONS)
        ) {
            getSharedPreferences("permissions", MODE_PRIVATE).edit()
                .putBoolean(Manifest.permission.POST_NOTIFICATIONS, true).apply()
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }

    /// Remote control has no dialog: Android only lets apps open its
    /// Accessibility settings (the page for one service is for system apps).
    /// The extras ask Settings to scroll to and highlight Linksy's row;
    /// phones that don't know them just show the list.
    private fun openControlSettings() {
        val component = android.content.ComponentName(this, ControlService::class.java).flattenToString()
        val args = android.os.Bundle().apply { putString(":settings:fragment_args_key", component) }
        startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .putExtra(":settings:fragment_args_key", component)
                .putExtra(":settings:show_fragment_args", args),
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        val (session, result) = pendingCapture ?: return
        pendingCapture = null
        if (resultCode == RESULT_OK && data != null) {
            ShareService.consents[session] = resultCode to data
            result.success(true)
        } else {
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        pendingPermissions.remove(requestCode)
            ?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    }

    private fun linkFrom(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == "linksy" && it.host == "pair" }?.toString()

    /// The name the user gave this phone, else its model ("Pixel 9").
    private fun deviceName(): String {
        val given = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        return given?.takeIf { it.isNotBlank() } ?: Build.MODEL
    }

    private companion object {
        const val REQUEST_CAPTURE = 41
        const val REQUEST_CAMERA = 42
        const val REQUEST_NOTIFICATIONS = 43
    }
}
