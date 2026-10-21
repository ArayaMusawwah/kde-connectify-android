package app.linksy

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File

/// Received files go to Downloads/Linksy (Android 10+), where the Files app
/// and every other app find them. MediaStore needs no permission for files
/// an app adds itself. Folders keep their shape: Downloads/Linksy/Photos/a.jpg.
object Downloads {
    /// Moves each received file (under [root]) into Downloads and returns
    /// where it went (`content://` URIs); a file that couldn't move keeps
    /// its path. Older Android keeps them all where they are.
    fun publish(context: Context, root: File, paths: List<String>): List<String> {
        if (Build.VERSION.SDK_INT < 29) return paths
        val resolver = context.contentResolver
        return paths.map { path ->
            val file = File(path)
            runCatching {
                val relative = file.parentFile?.canonicalPath?.removePrefix(root.canonicalPath)?.trim('/').orEmpty()
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, file.name)
                    put(MediaStore.Downloads.MIME_TYPE, ReceivedFiles.mime(file.name))
                    put(
                        MediaStore.Downloads.RELATIVE_PATH,
                        listOf(Environment.DIRECTORY_DOWNLOADS, "Linksy", relative).filter { it.isNotEmpty() }.joinToString("/"),
                    )
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)!!
                try {
                    resolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
                    resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                } catch (e: Exception) {
                    resolver.delete(uri, null, null)
                    throw e
                }
                file.delete()
                // Empty folders left behind in the app's folder go too.
                var dir = file.parentFile
                while (dir != null && dir.canonicalPath != root.canonicalPath && dir.list()?.isEmpty() == true) {
                    dir.delete()
                    dir = dir.parentFile
                }
                uri.toString()
            }.onFailure { Log.w("linksy", "couldn't move ${file.name} to Downloads", it) }.getOrDefault(path)
        }
    }
}
