package app.linksy

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import java.io.File

/// "Share → Linksy" lands here. Shared files are copied while this activity
/// still holds the read access the sharing app gave it, then the text or the
/// copies' paths go on to the app's one window, so a share never opens a
/// second copy of Linksy inside the sharing app.
class ShareTarget : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shared = intent
        @Suppress("DEPRECATION")
        val uris = buildList {
            shared.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(::addAll)
            if (isEmpty()) shared.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(::add)
            if (isEmpty()) shared.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(::add)
            }
        }
        val text = shared.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (uris.isEmpty()) {
            forward { if (!text.isNullOrBlank()) putExtra(EXTRA_TEXT, text) }
            return
        }
        Thread {
            val paths = copyUris(this, uris, "shared")
            runOnUiThread { forward { putExtra(EXTRA_FILES, paths.toTypedArray()) } }
        }.start()
    }

    private fun forward(fill: Intent.() -> Unit) {
        startActivity(
            Intent(this, MainActivity::class.java).setAction(ACTION_SHARED).apply(fill).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        finish()
    }

    companion object {
        const val ACTION_SHARED = "app.linksy.SHARED"
        const val EXTRA_TEXT = "app.linksy.text"
        const val EXTRA_FILES = "app.linksy.files"

        /// Copies content into the app's cache under [folder] (emptied first):
        /// the node sends from paths. Each in its own folder, so two with one
        /// name both keep it. Unreadable ones are left out.
        fun copyUris(context: Context, uris: List<Uri>, folder: String): List<String> {
            val dir = File(context.cacheDir, folder).apply { deleteRecursively(); mkdirs() }
            val resolver = context.contentResolver
            return uris.mapIndexedNotNull { i, uri ->
                runCatching {
                    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                        ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                        ?.replace('/', '_') ?: "file-$i"
                    val file = File(File(dir, "$i").apply { mkdirs() }, name)
                    resolver.openInputStream(uri)!!.use { input -> file.outputStream().use { input.copyTo(it) } }
                    file.path
                }.getOrNull()
            }
        }
    }
}
