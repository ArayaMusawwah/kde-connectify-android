package app.linksy

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.BatteryManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import app.linksy.files.FileServer
import app.linksy.files.NativeFiles
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
    /// Something shared to Linksy from another app (text or file copies),
    /// until Dart asks for it.
    private var pendingShare: Map<String, Any>? = null

    private val ring by lazy { RingPlayer(applicationContext) }
    private var calls: CallWatcher? = null
    /// Waiting on the photo picker: which device, and Dart's reply.
    private var pendingPicture: Pair<String, MethodChannel.Result>? = null
    /// Waiting on Android's folder picker: which folder, and Dart's reply.
    private var pendingFolder: Pair<String, MethodChannel.Result>? = null
    private var batteryReceiver: BroadcastReceiver? = null

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
        takeShared(intent)
        watchBattery()
        TransferNotice.answer = { transfer, accept ->
            runOnUiThread { channel?.invokeMethod("transferAnswer", mapOf("transfer" to transfer, "accept" to accept)) }
        }
        Push.subscribe()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.linksy/platform").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceName" -> result.success(deviceName())
                    "takeLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    "pictures" -> result.success(Pictures.all(this@MainActivity))
                    "pickPicture" -> pickPicture(call.argument<String>("device")!!, result)
                    "removePicture" -> {
                        Pictures.remove(this@MainActivity, call.argument<String>("device")!!)
                        result.success(null)
                    }
                    "pickFolder" -> pickFolder(call.argument<String>("kind")!!, result)
                    "folder" -> result.success(folderName(call.argument<String>("kind")!!))
                    "shareFiles" -> {
                        val on = call.argument<Boolean>("on") == true
                        fileServer(this@MainActivity).root = folder("files")
                        NativeFiles.sharing(on && folder("files") != null)
                        result.success(null)
                    }
                    "keepAlive" -> {
                        if (call.argument<Boolean>("on") == true) {
                            KeepAlive.start(this@MainActivity, call.argument<String>("text") ?: "Linksy is connected", call.argument<Boolean>("awake") == true)
                        } else {
                            KeepAlive.stop(this@MainActivity)
                        }
                        result.success(null)
                    }
                    "watchCalls" -> {
                        calls?.stop()
                        calls = null
                        if (call.argument<Boolean>("on") == true) {
                            calls = CallWatcher(applicationContext) { state -> channel?.invokeMethod("callState", state) }.apply { start() }
                        }
                        result.success(null)
                    }
                    "photoBatch" -> {
                        val tree = folder("photos") ?: return@setMethodCallHandler result.success(null)
                        val since = (call.argument<Number>("since") ?: 0).toLong()
                        Thread {
                            val batch = runCatching { PhotoScanner.batch(applicationContext, tree, since) }.getOrNull()
                            runOnUiThread { result.success(batch) }
                        }.start()
                    }
                    "presentation" -> {
                        presenting = call.argument<Boolean>("on") == true
                        if (presenting) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "prefs" -> result.success(
                        prefs().all.filterKeys { it.startsWith("app.") }.mapKeys { it.key.removePrefix("app.") },
                    )
                    "setPref" -> {
                        val key = "app." + call.argument<String>("key")!!
                        val value = call.argument<String>("value")
                        prefs().edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
                        result.success(null)
                    }
                    "takeShare" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    "battery" -> result.success(battery(null))
                    "noticeTransfer" -> {
                        TransferNotice.post(
                            this@MainActivity, call.argument<String>("transfer")!!,
                            call.argument<String>("title")!!, call.argument<String>("body") ?: "",
                        )
                        result.success(null)
                    }
                    "cancelNotice" -> {
                        TransferNotice.cancel(this@MainActivity, call.argument<String>("transfer")!!)
                        result.success(null)
                    }
                    "publishDownloads" -> {
                        val paths = call.argument<List<String>>("paths").orEmpty()
                        val root = java.io.File(getExternalFilesDir(null), "Received")
                        Thread {
                            val moved = Downloads.publish(applicationContext, root, paths)
                            runOnUiThread { result.success(moved) }
                        }.start()
                    }
                    "pushToken" -> Push.token { token -> runOnUiThread { result.success(token) } }
                    "openUrl" -> result.success(openUrl(call.argument<String>("url")!!))
                    "startRing" -> {
                        ring.start()
                        result.success(null)
                    }
                    "stopRing" -> {
                        ring.stop()
        calls?.stop()
                        result.success(null)
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
                    "switchCamera" -> {
                        ShareService.switchCamera(this@MainActivity, call.argument<String>("session")!!)
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

    /// Presentation remote: the volume keys change slides instead of volume.
    private var presenting = false

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        val code = event.keyCode
        if (presenting && (code == android.view.KeyEvent.KEYCODE_VOLUME_UP || code == android.view.KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == android.view.KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                channel?.invokeMethod("volumeKey", if (code == android.view.KeyEvent.KEYCODE_VOLUME_UP) "up" else "down")
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeShared(intent)
        val link = linkFrom(intent) ?: return
        channel?.invokeMethod("link", link) ?: run { pendingLink = link }
    }

    private fun prefs() = getSharedPreferences("linksy", MODE_PRIVATE)

    /// A folder the user picked for Linksy (`files` to share, `photos` to back
    /// up), if Android still grants it.
    private fun folder(kind: String): android.net.Uri? {
        val uri = prefs().getString("folder.$kind", null)?.let(android.net.Uri::parse) ?: return null
        return uri.takeIf { u -> contentResolver.persistedUriPermissions.any { it.uri == u && it.isReadPermission } }
    }

    private fun folderName(kind: String): String? {
        val tree = folder(kind) ?: return null
        val doc = android.provider.DocumentsContract.buildDocumentUriUsingTree(
            tree, android.provider.DocumentsContract.getTreeDocumentId(tree),
        )
        return runCatching {
            contentResolver.query(doc, arrayOf(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        }.getOrNull() ?: tree.lastPathSegment?.substringAfterLast(':')
    }

    /// Android's photo picker (no permission), or the document picker on
    /// phones without it.
    private fun pickPicture(device: String, result: MethodChannel.Result) {
        pendingPicture?.second?.success(null)
        pendingPicture = device to result
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(android.provider.MediaStore.ACTION_PICK_IMAGES)
        } else {
            Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICTURE)
    }

    /// Android's folder picker; the grant is kept across restarts.
    private fun pickFolder(kind: String, result: MethodChannel.Result) {
        pendingFolder?.second?.success(null)
        pendingFolder = kind to result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        if (kind == "photos" && Build.VERSION.SDK_INT >= 26) {
            intent.putExtra(
                android.provider.DocumentsContract.EXTRA_INITIAL_URI,
                android.provider.DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:DCIM"),
            )
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_FOLDER)
    }

    /// "Share → Linksy", handed over by [ShareTarget] (files already copied).
    private fun takeShared(intent: Intent?) {
        if (intent?.action != ShareTarget.ACTION_SHARED) return
        // Handled once, even if the activity is recreated with this intent.
        setIntent(Intent(Intent.ACTION_MAIN))
        val files = intent.getStringArrayExtra(ShareTarget.EXTRA_FILES)?.toList().orEmpty()
        val text = intent.getStringExtra(ShareTarget.EXTRA_TEXT)
        when {
            files.isNotEmpty() -> deliverShare(mapOf("files" to files))
            !text.isNullOrBlank() -> deliverShare(mapOf("text" to text))
        }
    }

    private fun deliverShare(share: Map<String, Any>) {
        val c = channel
        if (c == null) pendingShare = share else c.invokeMethod("share", share)
    }

    /// Battery changes go to Dart, which tells paired computers (docs/protocol.md
    /// §4.5: on connecting, every 5 points, plugging in or out).
    private fun watchBattery() {
        if (batteryReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                battery(intent)?.let { channel?.invokeMethod("batteryChanged", it) }
            }
        }
        batteryReceiver = receiver
        // A system broadcast: no export flag needed, and no permission.
        registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    }

    /// Level in percent and whether it's charging; the sticky broadcast when
    /// [intent] is null.
    private fun battery(intent: Intent?): Map<String, Any>? {
        val i = intent ?: registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        val status = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        return mapOf("level" to (level * 100 / scale).coerceIn(0, 100), "charging" to charging)
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
        TransferNotice.answer = null
        batteryReceiver?.let { runCatching { unregisterReceiver(it) } }
        batteryReceiver = null
        ring.stop()
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
        // The whole screen only: Android 14+ otherwise preselects "A single
        // app", which leaves the status bar, notifications and quick settings
        // black on the computer.
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            manager.createScreenCaptureIntent(android.media.projection.MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_CAPTURE)
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

    /// A link a computer sent, in the browser. Web links only.
    private fun openUrl(url: String): Boolean {
        val uri = android.net.Uri.parse(url.trim())
        if (uri.scheme?.lowercase() !in setOf("http", "https")) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
            true
        } catch (e: android.content.ActivityNotFoundException) {
            false
        }
    }

    /// Opens a received file in another app: "done", "missing" or "noApp".
    private fun openFile(path: String): String {
        if (path.startsWith("content://")) {
            val uri = android.net.Uri.parse(path)
            val type = contentResolver.getType(uri) ?: return "missing"
            val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            return try {
                startActivity(Intent.createChooser(view, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                "done"
            } catch (e: android.content.ActivityNotFoundException) {
                "noApp"
            }
        }
        val file = java.io.File(path)
        if (!file.isFile) return "missing"
        val root = java.io.File(getExternalFilesDir(null), "Received").canonicalPath
        val relative = file.canonicalPath.removePrefix(root).trimStart('/')
        val uri = android.net.Uri.Builder().scheme("content").authority(ReceivedFiles.authority(this))
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
        if (requestCode == REQUEST_PICTURE) {
            val (device, result) = pendingPicture ?: return
            pendingPicture = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) return result.success(null)
            Thread {
                val path = Pictures.save(applicationContext, device, uri)
                runOnUiThread { result.success(path) }
            }.start()
            return
        }
        if (requestCode == REQUEST_FOLDER) {
            val (kind, result) = pendingFolder ?: return
            pendingFolder = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) return result.success(null)
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                (if (kind == "files") Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0)
            runCatching { contentResolver.takePersistableUriPermission(uri, flags) }
            // Let go of the folder this replaces.
            prefs().getString("folder.$kind", null)?.takeIf { it != uri.toString() }?.let { old ->
                val stillUsed = listOf("files", "photos").any { it != kind && prefs().getString("folder.$it", null) == old }
                if (!stillUsed) runCatching {
                    contentResolver.releasePersistableUriPermission(
                        android.net.Uri.parse(old),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                }
            }
            prefs().edit().putString("folder.$kind", uri.toString()).apply()
            if (kind == "files") fileServer(this).root = uri
            return result.success(folderName(kind))
        }
        if (requestCode == REQUEST_PICK) {
            val result = pendingPick ?: return
            pendingPick = null
            val uris = buildList {
                data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
                if (isEmpty()) data?.data?.let(::add)
            }
            if (resultCode != RESULT_OK || uris.isEmpty()) return result.success(emptyList<String>())
            Thread { val paths = ShareTarget.copyUris(this, uris, "picked"); runOnUiThread { result.success(paths) } }.start()
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
        const val REQUEST_FOLDER = 45
        const val REQUEST_PICTURE = 46

        private var files: FileServer? = null

        /// One file server per process, whatever happens to the activity.
        fun fileServer(context: Context): FileServer =
            files ?: FileServer(context.applicationContext).also { files = it; it.start() }
    }
}
