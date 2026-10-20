package app.linksy

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Photo auto-import (docs/protocol.md §4.5): new photos and videos in the folder the
/// user chose (their camera folder, through Android's picker: no storage
/// permission), copied into month folders (`2026-10/IMG_1.jpg`) for the node
/// to send. Oldest first, a batch at a time.
object PhotoScanner {
    /// Copies of what changed after [sinceMs] (at most [limit] files, and about
    /// 300 MB), as the month folders to send, and the newest time among them.
    fun batch(context: Context, tree: Uri, sinceMs: Long, limit: Int = 40): Map<String, Any> {
        val resolver = context.contentResolver
        val found = mutableListOf<Triple<String, String, Long>>() // doc id, name, modified
        val columns = arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE, Document.COLUMN_LAST_MODIFIED,
        )
        val pending = ArrayDeque(listOf(DocumentsContract.getTreeDocumentId(tree)))
        while (pending.isNotEmpty()) {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, pending.removeFirst())
            resolver.query(children, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val name = c.getString(1) ?: continue
                    val mime = c.getString(2) ?: ""
                    val modified = if (c.isNull(3)) 0L else c.getLong(3)
                    when {
                        mime == Document.MIME_TYPE_DIR -> if (!name.startsWith(".")) pending.add(c.getString(0))
                        (mime.startsWith("image/") || mime.startsWith("video/")) && modified > sinceMs && !name.startsWith(".") ->
                            found += Triple(c.getString(0), name, modified)
                    }
                }
            }
        }
        found.sortBy { it.third }
        val dir = File(context.cacheDir, "import").apply { deleteRecursively(); mkdirs() }
        val month = SimpleDateFormat("yyyy-MM", Locale.ROOT)
        var bytes = 0L
        var newest = sinceMs
        var count = 0
        for ((id, name, modified) in found) {
            if (count >= limit || bytes > 300L * 1024 * 1024) break
            val folder = File(dir, month.format(Date(modified))).apply { mkdirs() }
            val file = File(folder, name.replace('/', '_'))
            runCatching {
                resolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, id))!!.use { input ->
                    file.outputStream().use { input.copyTo(it) }
                }
                bytes += file.length()
                newest = maxOf(newest, modified)
                count++
            }
        }
        return mapOf(
            "folders" to (dir.listFiles()?.filter { it.isDirectory && (it.list()?.isNotEmpty() == true) }?.map { it.path } ?: emptyList()),
            "newest" to newest,
            "count" to count,
            "more" to (found.size > count),
        )
    }
}
