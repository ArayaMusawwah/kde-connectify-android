package app.linksy.media

/// The Rust side of a media session (rust/src/sessions.rs): video and input
/// go straight to and from the session's QUIC stream, not through Dart.
object NativeSession {
    init {
        System.loadLibrary("linksy_bridge")
    }

    /// False once the session is gone: the viewer stopped or the link dropped.
    /// Blocks while the network is behind, which paces the encoder.
    external fun write(session: String, data: ByteArray): Boolean

    /// The next bytes from the other side (input frames for `control`, video
    /// for `display`), blocking; null once the session is over.
    external fun read(session: String): ByteArray?

    /// Tells the computer what the camera in [session] can do and how it's
    /// set (`camera_state`, docs/android-app.md §2.8).
    external fun cameraState(session: String, json: String)

    /// Ends this side of the stream; the core then reports the session ended.
    external fun finish(session: String)
}
