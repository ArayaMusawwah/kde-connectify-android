package app.linksy

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.io.File
import java.security.MessageDigest

/// Update Now: installs a downloaded APK over this app with Android's own
/// installer, once its SHA-256 matches the one the release lists. Android
/// asks "Update this app?" and refuses an APK not signed with Linksy's key.
object Updater {
    /// Called with `installed`, `cancelled`, `bad_sum`, or `failed:<message>`.
    var onStatus: ((String) -> Unit)? = null

    /// Whether the person let Linksy install updates (Install unknown apps).
    fun allowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls()

    /// Opens Install unknown apps for Linksy.
    fun allow(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /// The ABI this phone prefers, for choosing the smaller APK.
    fun abi(): String? = Build.SUPPORTED_ABIS.firstOrNull()

    /// Checks [path] against [sha256], then hands it to the installer. Runs off
    /// the main thread; the outcome comes through [onStatus].
    fun install(context: Context, path: String, sha256: String) {
        val app = context.applicationContext
        Thread {
            val file = File(path)
            if (!file.isFile || digest(file) != sha256.lowercase()) {
                file.delete()
                return@Thread report("bad_sum")
            }
            runCatching {
                val installer = app.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                    .apply { setAppPackageName(app.packageName) }
                    .apply { if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED) }
                val id = installer.createSession(params)
                installer.openSession(id).use { session ->
                    session.openWrite("linksy.apk", 0, file.length()).use { out ->
                        file.inputStream().use { it.copyTo(out) }
                        session.fsync(out)
                    }
                    val status = PendingIntent.getBroadcast(
                        app, id, Intent(app, Status::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                    )
                    session.commit(status.intentSender)
                }
            }.onFailure {
                Log.w("linksy", "update not installed ($it)")
                report("failed:${it.message ?: it.javaClass.simpleName}")
            }
        }.start()
    }

    private fun digest(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                md.update(buffer, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun report(status: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { onStatus?.invoke(status) }
    }

    /// The installer's answer: ask the person when it needs to, else report.
    class Status : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    else intent.getParcelableExtra(Intent.EXTRA_INTENT)) ?: return report("failed:no confirmation")
                    context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                // Not seen when Android restarts Linksy into the new version.
                PackageInstaller.STATUS_SUCCESS -> report("installed")
                PackageInstaller.STATUS_FAILURE_ABORTED -> report("cancelled")
                else -> {
                    val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
                    Log.w("linksy", "update not installed: $message")
                    report("failed:$message")
                }
            }
        }
    }
}
