package app.linksy

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.system.Os
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
        // Picked as a device in the share sheet: straight to it.
        val device = ShareShortcuts.deviceOf(shared)
        if (uris.isEmpty()) {
            forward(device) { if (!text.isNullOrBlank()) putExtra(EXTRA_TEXT, text) }
            return
        }
        Thread {
            val paths = copyUris(this, uris, "shared")
            runOnUiThread { forward(device) { putExtra(EXTRA_FILES, paths.toTypedArray()) } }
        }.start()
    }

    private fun forward(device: String?, fill: Intent.() -> Unit) {
        startActivity(
            Intent(this, MainActivity::class.java).setAction(ACTION_SHARED).apply(fill)
                .apply { if (device != null) putExtra(EXTRA_DEVICE, device) }.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        finish()
    }

    companion object {
        const val ACTION_SHARED = "app.linksy.SHARED"
        const val EXTRA_TEXT = "app.linksy.text"
        const val EXTRA_FILES = "app.linksy.files"
        const val EXTRA_DEVICE = "app.linksy.device"

        /// Hands content over to the node, which sends from paths: each file
        /// as a link, under its own name, to a descriptor kept open here, so
        /// nothing is copied first (a long video would need its own size free
        /// again, and the transfer waits for the copy). Content that isn't a
        /// plain file (some cloud documents) is copied into the cache instead.
        /// Each hand-over gets its own folder under [folder], so a transfer
        /// still waiting keeps its files; folders a day old go, with their
        /// descriptors. Unreadable ones are left out.
        fun copyUris(context: Context, uris: List<Uri>, folder: String): List<String> {
            val root = File(context.cacheDir, folder).apply { mkdirs() }
            sweep(root)
            val dir = File(root, "${System.currentTimeMillis()}").apply { mkdirs() }
            val kept = mutableListOf<ParcelFileDescriptor>()
            val resolver = context.contentResolver
            val paths = uris.mapIndexedNotNull { i, uri ->
                runCatching {
                    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                        ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                        ?.replace('/', '_') ?: "file-$i"
                    val file = File(File(dir, "$i").apply { mkdirs() }, name)
                    val fd = runCatching { resolver.openFileDescriptor(uri, "r") }.getOrNull()
                    if (fd != null && fd.statSize >= 0) {
                        Os.symlink("/proc/self/fd/${fd.fd}", file.path)
                        kept += fd
                    } else {
                        fd?.close()
                        resolver.openInputStream(uri)!!.use { input -> file.outputStream().use { input.copyTo(it) } }
                    }
                    file.path
                }.getOrNull()
            }
            synchronized(open) { open[dir.path] = kept }
            return paths
        }

        /// Descriptors behind each hand-over folder, closed when it goes.
        private val open = mutableMapOf<String, List<ParcelFileDescriptor>>()

        private fun sweep(root: File) {
            val old = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
            for (dir in root.listFiles().orEmpty()) {
                val made = dir.name.toLongOrNull()
                // From an older run (its links lead nowhere now), or a day old.
                val stale = synchronized(open) { dir.path !in open } || made == null || made < old
                if (!stale) continue
                synchronized(open) { open.remove(dir.path) }?.forEach { runCatching { it.close() } }
                dir.deleteRecursively()
            }
        }
    }
}
