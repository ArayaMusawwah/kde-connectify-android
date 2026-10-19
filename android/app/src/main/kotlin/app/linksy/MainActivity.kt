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
import app.linksy.media.DisplayReceiver
import app.linksy.media.NativeSession
import app.linksy.media.QrScanner
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
                    // True once per install: whether to show the permissions sheet.
                    "firstPermissionsVisit" -> {
                        val prefs = getSharedPreferences("permissions", MODE_PRIVATE)
                        val first = !prefs.getBoolean("sheet_shown", false)
                        if (first) prefs.edit().putBoolean("sheet_shown", true).apply()
                        result.success(first)
                    }
                    "permissions" -> result.success(
                        mapOf(
                            "notifications" to (Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)),
                            "camera" to granted(Manifest.permission.CAMERA),
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
                    // Where the node and history live, and where received files go.
                    "paths" -> result.success(
                        mapOf("support" to filesDir.path, "external" to getExternalFilesDir(null)?.path),
                    )
                    "pickFiles" -> pickFiles(result)
                    "openFile" -> result.success(openFile(call.argument<String>("path")!!))
                    "startScanner" -> result.success(startScanner())
                    "stopScanner" -> {
                        scanner?.stop()
                        scanner = null
                        result.success(null)
                    }
                    "scannerTorch" -> {
                        scanner?.setTorch(call.argument<Boolean>("on") == true)
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
        scanner?.stop()
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

    private var scanner: QrScanner? = null
    private var pendingPick: MethodChannel.Result? = null

    /// The pairing QR scanner, previewed into a new Flutter texture.
    private fun startScanner(): Map<String, Any>? {
        scanner?.stop()
        val producer = engine?.renderer?.createSurfaceProducer() ?: return null
        val s = QrScanner(
            this, producer,
            onCode = { text -> runOnUiThread { channel?.invokeMethod("qrCode", text) } },
            onError = { message -> runOnUiThread { channel?.invokeMethod("scannerError", message) } },
        )
        scanner = s
        return mapOf("texture" to producer.id(), "width" to s.size.width, "height" to s.size.height, "rotation" to s.rotation)
    }

    /// Android's document picker. The node sends from paths, so the picks are
    /// copied into the app's cache first (docs/protocol.md §7: no reader API yet).
    private fun pickFiles(result: MethodChannel.Result) {
        pendingPick?.success(emptyList<String>())
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICK)
    }

    private fun copyPicks(uris: List<android.net.Uri>): List<String> {
        val dir = java.io.File(cacheDir, "picked").apply { deleteRecursively(); mkdirs() }
        return uris.mapIndexedNotNull { i, uri ->
            runCatching {
                val name = contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                    ?.replace('/', '_') ?: "file-$i"
                // Each in its own folder, so two picks with one name both keep it.
                val file = java.io.File(java.io.File(dir, "$i").apply { mkdirs() }, name)
                contentResolver.openInputStream(uri)!!.use { input -> file.outputStream().use { input.copyTo(it) } }
                file.path
            }.getOrNull()
        }
    }

    /// Opens a received file in another app: "done", "missing" or "noApp".
    private fun openFile(path: String): String {
        val file = java.io.File(path)
        if (!file.isFile) return "missing"
        val root = java.io.File(getExternalFilesDir(null), "Received").canonicalPath
        val relative = file.canonicalPath.removePrefix(root).trimStart('/')
        val uri = android.net.Uri.Builder().scheme("content").authority(ReceivedFiles.AUTHORITY)
            .encodedPath("/" + relative.split('/').joinToString("/") { android.net.Uri.encode(it) }).build()
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, ReceivedFiles.mime(file.name))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            startActivity(Intent.createChooser(view, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            "done"
        } catch (e: android.content.ActivityNotFoundException) {
            "noApp"
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK) {
            val result = pendingPick ?: return
            pendingPick = null
            val uris = buildList {
                data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
                if (isEmpty()) data?.data?.let(::add)
            }
            if (resultCode != RESULT_OK || uris.isEmpty()) return result.success(emptyList<String>())
            Thread { val paths = copyPicks(uris); runOnUiThread { result.success(paths) } }.start()
            return
        }
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
        const val REQUEST_PICK = 44
    }
}
