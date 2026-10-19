package app.linksy.media

/// The Rust side of a media session (rust/src/sessions.rs): encoded video goes
/// straight into the session's QUIC stream, not through Dart.
object NativeSession {
    init {
        System.loadLibrary("linksy_bridge")
    }

    /// False once the session is gone: the viewer stopped or the link dropped.
    external fun write(session: String, data: ByteArray): Boolean

    /// Ends this side of the stream; the core then reports the session ended.
    external fun finish(session: String)
}
