package app.linksy.files

/// The Rust side of file sharing (rust/src/files.rs): requests from a
/// computer browsing this phone, pulled one at a time.
object NativeFiles {
    init {
        System.loadLibrary("linksy_bridge")
    }

    /// The next request as JSON, blocking; null when the node is gone.
    external fun next(): String?

    /// A write's bytes.
    external fun body(id: Long): ByteArray?

    /// The answer: `{"type":"fs_entries",…}` and so on, plus a read's bytes.
    external fun reply(id: Long, json: String, data: ByteArray?)

    /// Whether requests reach [FileServer] at all.
    external fun sharing(on: Boolean)
}
