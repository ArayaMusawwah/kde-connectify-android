package org.kde.connectify.files

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.util.Log
import android.webkit.MimeTypeMap
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/// Handles file operations from the desktop: read, write, list, mkdir, delete, rename.
/// Two modes:
/// - Picker mode (`allFiles=false`): SAF document URI pointing to one user-chosen folder.
/// - All-files mode (`allFiles=true`): direct java.io.File access to `/storage/emulated/0`
///   when `MANAGE_EXTERNAL_STORAGE` is granted by the user.
class FileServer(private val context: Context) {
    /// True when the user has granted MANAGE_EXTERNAL_STORAGE.
    @Volatile var allFiles: Boolean = false

    /// In picker mode, the SAF tree URI. Null means "no folder is shared yet".
    @Volatile var root: Uri? = null

    /// The absolute path to the top of what we share (picker: a subdir; all-files: /storage/emulated/0).
    private var sharePath: String = ""

    private val resolver get() = context.contentResolver

    init {
        if (Environment.isExternalStorageManager()) {
            allFiles = true
            sharePath = Environment.getExternalStorageDirectory().absolutePath
            Log.i("KDEConnectify", "FileServer: MANAGE_EXTERNAL_STORAGE is active, root set to $sharePath")
        }
    }

    fun enableAllFiles(on: Boolean) {
        if (on) {
            // Verify actual permission before enabling.
            if (Environment.isExternalStorageManager()) {
                allFiles = true
                sharePath = Environment.getExternalStorageDirectory().absolutePath
                root = null // not used in all-files mode
                Log.i("KDEConnectify", "FileServer: enabled allFiles -> $sharePath")
            } else {
                Log.w("KDEConnectify", "setAllFiles=true but MANAGE_EXTERNAL_STORAGE not granted")
            }
        } else {
            allFiles = false
            sharePath = ""
            Log.i("KDEConnectify", "FileServer: disabled allFiles")
        }
    }

    fun allFilesGranted(): Boolean = Environment.isExternalStorageManager()

    fun start(workers: Int = 3) {
        repeat(workers) { n -> Thread({ loop() }, "linksy-files-$n").apply { isDaemon = true; start() } }
    }

    private fun loop() {
        while (true) {
            val raw = NativeFiles.next() ?: return
            val request = runCatching { JSONObject(raw) }.getOrNull() ?: continue
            val id = request.getLong("id")
            try {
                handle(id, request)
            } catch (e: Exception) {
                Log.w("linksy", "file request failed", e)
                error(id, e.message ?: "That didn't work on the phone.")
            }
        }
    }

    private fun handle(id: Long, r: JSONObject) {
        val path = r.optString("path", "/")
        if (allFiles) {
            handleAllFiles(id, r, path)
        } else {
            handlePicker(id, r, path)
        }
    }

    // ── All-files mode (direct File IO) ──────────────────────────────────────

    private fun handleAllFiles(id: Long, r: JSONObject, path: String) {
        val shareRoot = File(sharePath)
        val op = r.getString("op")
        Log.i("KDEConnectify", "FileServer allFiles op=$op path=$path shareRoot=$sharePath")
        when (op) {
            "info" -> reply(id, JSONObject().put("type", "fs_info").put("name", shareRoot.name))
            "list" -> {
                val dir = resolveFile(shareRoot, path) ?: return notFound(id, path)
                if (!dir.isDirectory) return error(id, "That's a file, not a folder.")
                val entries = JSONArray()
                dir.listFiles()?.forEach { f ->
                    entries.put(entryJson(f))
                }
                reply(id, JSONObject().put("type", "fs_entries").put("entries", entries))
            }
            "stat" -> {
                val f = resolveFile(shareRoot, path) ?: return notFound(id, path)
                reply(id, JSONObject().put("type", "fs_entry").put("entry", entryJson(f)))
            }
            "read" -> {
                val f = resolveFile(shareRoot, path) ?: return notFound(id, path)
                val offset = r.getLong("offset")
                val length = r.getLong("length").coerceAtMost(4L shl 20).toInt()
                val bytes = FileInputStream(f).channel.use { ch ->
                    ch.position(offset)
                    val buf = java.nio.ByteBuffer.allocate(length)
                    while (buf.hasRemaining() && ch.read(buf) > 0) Unit
                    buf.array().copyOf(buf.position())
                }
                NativeFiles.reply(id, JSONObject().put("type", "fs_data").put("length", bytes.size).toString(), bytes)
            }
            "write" -> {
                val body = NativeFiles.body(id) ?: return error(id, "The data didn't arrive.")
                val offset = r.getLong("offset")
                val dir = resolveFile(shareRoot, parent(path)) ?: return notFound(id, parent(path))
                val f = File(dir, name(path)); f.createNewFile()
                FileOutputStream(f).channel.use { ch ->
                    ch.position(offset)
                    ch.write(java.nio.ByteBuffer.wrap(body))
                    if (r.optBoolean("truncate")) ch.truncate(offset + body.size)
                }
                ok(id)
            }
            "mkdir" -> {
                val p = resolveFile(shareRoot, parent(path)) ?: return notFound(id, parent(path))
                val dir = File(p, name(path)); dir.mkdir(); if (dir.exists()) ok(id) else error(id, "Couldn't create the folder.")
            }
            "delete" -> {
                val f = resolveFile(shareRoot, path) ?: return notFound(id, path)
                if (f.deleteRecursively()) ok(id) else error(id, "Couldn't delete ${f.name}.")
            }
            "rename" -> {
                val f = resolveFile(shareRoot, path) ?: return notFound(id, path)
                val to = r.getString("to")
                val dest = File(f.parentFile, name(to))
                if (f.renameTo(dest)) ok(id) else error(id, "Couldn't rename ${f.name}.")
            }
            else -> error(id, "This phone can't do that yet.")
        }
    }

    /// Resolve absolute path (as seen by desktop, starts with "/") to a File.
    private fun resolveFile(root: File, path: String): File? {
        val rel = path.removePrefix("/")
        val f = if (rel.isEmpty()) root else File(root, rel)
        // Safety: ensure f is inside root
        return if (f.canonicalPath.startsWith(root.canonicalPath)) f else null
    }

    // ── Picker mode (SAF document URI) ─────────────────────────────────────────

    private fun handlePicker(id: Long, r: JSONObject, path: String) {
        val tree = root ?: return error(id, "No folder is shared. Pick a folder in the app's settings.")
        when (r.getString("op")) {
            "info" -> reply(id, JSONObject().put("type", "fs_info").put("name", find(tree, "/")?.name ?: ""))
            "list" -> {
                val doc = find(tree, path) ?: return notFound(id, path)
                if (!doc.dir) return error(id, "That's a file, not a folder.")
                val entries = JSONArray()
                children(tree, doc.id).forEach { entries.put(it.json()) }
                reply(id, JSONObject().put("type", "fs_entries").put("entries", entries))
            }
            "stat" -> {
                val doc = find(tree, path) ?: return notFound(id, path)
                reply(id, JSONObject().put("type", "fs_entry").put("entry", doc.json()))
            }
            "read" -> {
                val doc = find(tree, path) ?: return notFound(id, path)
                val offset = r.getLong("offset")
                val length = r.getLong("length").coerceAtMost(4L shl 20).toInt()
                val bytes = resolver.openFileDescriptor(uri(tree, doc.id), "r")!!.use { pfd ->
                    FileInputStream(pfd.fileDescriptor).channel.use { ch ->
                        ch.position(offset)
                        val buf = java.nio.ByteBuffer.allocate(length)
                        while (buf.hasRemaining() && ch.read(buf) > 0) Unit
                        buf.array().copyOf(buf.position())
                    }
                }
                NativeFiles.reply(id, JSONObject().put("type", "fs_data").put("length", bytes.size).toString(), bytes)
            }
            "write" -> {
                val body = NativeFiles.body(id) ?: return error(id, "The data didn't arrive.")
                val offset = r.getLong("offset")
                val existing = find(tree, path)
                val docId = existing?.id ?: create(tree, path, dir = false) ?: return error(id, "Couldn't create ${name(path)}.")
                resolver.openFileDescriptor(uri(tree, docId), "rw")!!.use { pfd ->
                    FileOutputStream(pfd.fileDescriptor).channel.use { ch ->
                        ch.position(offset)
                        ch.write(java.nio.ByteBuffer.wrap(body))
                        if (r.optBoolean("truncate")) ch.truncate(offset + body.size)
                    }
                }
                ok(id)
            }
            "mkdir" -> if (find(tree, path) != null || create(tree, path, dir = true) != null) ok(id) else error(id, "Couldn't create the folder.")
            "delete" -> {
                val doc = find(tree, path) ?: return notFound(id, path)
                if (path.trim('/').isEmpty()) return error(id, "The shared folder itself can't be deleted.")
                try {
                    android.provider.DocumentsContract.deleteDocument(resolver, uri(tree, doc.id))
                    forget(path)
                    ok(id)
                } catch (e: Exception) {
                    error(id, "Couldn't delete ${doc.name}.")
                }
            }
            "rename" -> {
                val to = r.getString("to")
                val doc = find(tree, path) ?: return notFound(id, path)
                if (parent(path) == parent(to)) {
                    try {
                        android.provider.DocumentsContract.renameDocument(resolver, uri(tree, doc.id), name(to))
                            ?: return error(id, "Couldn't rename it.")
                    } catch (e: Exception) {
                        return error(id, "Couldn't rename ${doc.name}.")
                    }
                } else {
                    return error(id, "Moving between folders is not supported yet.")
                }
                forget(path)
                ok(id)
            }
            else -> error(id, "This phone can't do that yet.")
        }
    }

    // ── JSON helpers ───────────────────────────────────────────────────────────

    private fun entryJson(f: File): JSONObject = JSONObject()
        .put("name", f.name)
        .put("dir", f.isDirectory)
        .put("size", if (f.isDirectory) 0 else f.length())
        .put("modified_ms", f.lastModified())

    private fun parent(path: String): String = "/" + path.split('/').filter { it.isNotEmpty() }.dropLast(1).joinToString("/").ifEmpty { "/" }
    private fun name(path: String): String = path.trimEnd('/').substringAfterLast('/')

    // ── SAF helpers (picker mode) ───────────────────────────────────────────────

    private class Doc(val id: String, val name: String, val dir: Boolean, val size: Long, val modified: Long) {
        fun json(): JSONObject = JSONObject().put("name", name).put("dir", dir)
            .put("size", if (dir) 0 else size).put("modified_ms", modified)
    }

    private val columns = arrayOf(
        android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE,
        android.provider.DocumentsContract.Document.COLUMN_SIZE,
        android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED,
    )

    private val ids = java.util.concurrent.ConcurrentHashMap<String, String>()

    private fun forget(path: String) {
        val key = normalize(path)
        ids.keys.removeIf { it == key || it.startsWith("$key/") }
    }

    private fun normalize(path: String) = "/" + path.split('/').filter { it.isNotEmpty() }.joinToString("/")

    private fun uri(tree: Uri, docId: String) = android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, docId)
    private fun rootId(tree: Uri) = android.provider.DocumentsContract.getTreeDocumentId(tree)

    private fun find(tree: Uri, path: String): Doc? {
        val key = normalize(path)
        ids[key]?.let { id -> query(tree, id)?.let { return it } }
        var doc = query(tree, rootId(tree))?.let { Doc(it.id, "", true, 0, it.modified) } ?: return null
        var at = ""
        for (part in key.split('/').filter { it.isNotEmpty() }) {
            at += "/$part"
            doc = children(tree, doc.id).firstOrNull { it.name == part } ?: return null
            ids[at] = doc.id
        }
        return doc
    }

    private fun doc(c: android.database.Cursor) = Doc(
        id = c.getString(0), name = c.getString(1) ?: "",
        dir = c.getString(2) == android.provider.DocumentsContract.Document.MIME_TYPE_DIR,
        size = if (c.isNull(3)) 0 else c.getLong(3),
        modified = if (c.isNull(4)) 0 else c.getLong(4),
    )

    private fun query(tree: Uri, docId: String): Doc? =
        runCatching {
            resolver.query(uri(tree, docId), columns, null, null, null)?.use { c -> if (c.moveToFirst()) doc(c) else null }
        }.getOrNull()

    private fun children(tree: Uri, docId: String): List<Doc> {
        val uri = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
        return resolver.query(uri, columns, null, null, null)?.use { c ->
            buildList { while (c.moveToNext()) add(doc(c)) }
        }.orEmpty()
    }

    private fun create(tree: Uri, path: String, dir: Boolean): String? {
        val parent = find(tree, parent(path))?.takeIf { it.dir } ?: return null
        val n = name(path)
        val mime = if (dir) android.provider.DocumentsContract.Document.MIME_TYPE_DIR else
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(n.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"
        val created = android.provider.DocumentsContract.createDocument(resolver, uri(tree, parent.id), mime, n) ?: return null
        val id = android.provider.DocumentsContract.getDocumentId(created)
        ids[normalize(path)] = id
        return id
    }

    // ── Reply helpers ───────────────────────────────────────────────────────────

    private fun reply(id: Long, json: JSONObject) = NativeFiles.reply(id, json.toString(), null)
    private fun ok(id: Long) = reply(id, JSONObject().put("type", "fs_ok"))
    private fun error(id: Long, message: String, notFound: Boolean = false) =
        reply(id, JSONObject().put("type", "fs_error").put("message", message).put("not_found", notFound))
    private fun notFound(id: Long, path: String) = error(id, "${normalize(path)} isn't there.", notFound = true)
}
