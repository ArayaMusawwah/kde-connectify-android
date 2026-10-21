package app.linksy

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max

/// Files on the clipboard and the picture this phone sends of itself
/// (docs/protocol.md §4.5).
object Clip {
    /// Puts [path] on Android's clipboard as a `content://` URI that apps
    /// pasting it may read. Received files outside Received are copied there.
    fun put(context: Context, path: String): Boolean = runCatching {
        val root = File(context.getExternalFilesDir(null), "Received").canonicalFile
        var file = File(path).canonicalFile
        if (!file.path.startsWith(root.path + File.separator)) {
            val dir = File(root, "Clipboard").apply { mkdirs() }
            file = File(dir, file.name).also { file.copyTo(it, overwrite = true) }
        }
        val relative = file.path.removePrefix(root.path + File.separator)
        val uri = Uri.Builder().scheme("content").authority(ReceivedFiles.authority(context))
            .path(relative).build()
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, file.name, uri))
        true
    }.getOrDefault(false)

    /// [path] (a saved picture) as a JPEG of at most 128 KiB, base64.
    fun pictureJpeg(path: String): String? = runCatching {
        val source = BitmapFactory.decodeFile(path) ?: return null
        var side = 512
        while (true) {
            val scale = side.toDouble() / max(source.width, source.height)
            val bitmap = if (scale < 1) {
                Bitmap.createScaledBitmap(source, (source.width * scale).toInt(), (source.height * scale).toInt(), true)
            } else {
                source
            }
            for (quality in intArrayOf(85, 70, 55)) {
                val out = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
                if (out.size() <= 128 * 1024) return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
            }
            side = side * 3 / 4
            if (side < 96) return null
        }
        @Suppress("UNREACHABLE_CODE")
        null
    }.getOrNull()
}
