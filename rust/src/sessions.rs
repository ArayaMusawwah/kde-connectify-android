//! Accepted media sessions, by id, for Android's media code to use straight
//! through JNI (`app.linksy.media.NativeSession`), not through Dart:
//!
//! - `screen`, `camera`: the phone writes H.264; nothing comes back.
//! - `control`: the phone writes H.264 and reads framed input messages.
//! - `display`: the phone reads H.264 and writes framed input messages.
//! - `input`: the phone (touchpad, keyboard) writes framed input messages.
//! - `screen` / `control` the phone asked for: it reads the computer's H.264
//!   and, for `control`, writes framed input messages.
//!
//! Each session gets a task that owns its streams: it writes what the app
//! queues and hands what arrives to the app, until either side ends.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use linksy_core::{Node, Session, SessionKind};
use tokio::sync::{Notify, mpsc};

use crate::api::node::rt;

struct Handle {
    /// Taken to end the session: a reader blocked in `read` may still hold
    /// the handle, so ending can't wait for it to be dropped.
    out: Mutex<Option<mpsc::Sender<Vec<u8>>>>,
    /// What the other side sent, for kinds where the phone reads.
    incoming: Mutex<Option<mpsc::Receiver<Vec<u8>>>>,
    /// Wakes the session's task if it's waiting on a reader that stopped.
    closed: Arc<Notify>,
}

fn sessions() -> &'static Mutex<HashMap<String, Arc<Handle>>> {
    static MAP: OnceLock<Mutex<HashMap<String, Arc<Handle>>>> = OnceLock::new();
    MAP.get_or_init(Default::default)
}

/// Keeps every session the user accepted, until it ends.
pub(crate) fn collect(node: &Node) {
    let Some(mut accepted) = node.incoming_sessions() else { return };
    rt().spawn(async move {
        while let Some(session) = accepted.recv().await {
            run(session);
        }
    });
}

pub(crate) fn run(mut session: Session) {
    let id = session.id.to_string();
    // The phone reads video when it watches (a second display, or a computer's
    // screen it asked for), and input when it's controlled. An `input`
    // session only writes.
    let watching = !session.sharing && session.kind != SessionKind::Input;
    // A computer may send `camera_control` on a camera session (docs/android-app.md).
    let reads = watching || (session.sharing && matches!(session.kind, SessionKind::Control | SessionKind::Camera));
    // Video in ends the session when the sharer stops.
    let ends_with_input = watching;
    let (out, mut queued) = mpsc::channel::<Vec<u8>>(32);
    let (arrived, incoming) = mpsc::channel::<Vec<u8>>(256);
    let closed = Arc::new(Notify::new());
    sessions().lock().unwrap().insert(
        id.clone(),
        Arc::new(Handle {
            out: Mutex::new(Some(out)),
            incoming: Mutex::new(reads.then_some(incoming)),
            closed: closed.clone(),
        }),
    );

    rt().spawn(async move {
        let mut buf = vec![0u8; 64 * 1024];
        let mut reading = true;
        let Session { send, recv, .. } = &mut session;
        loop {
            tokio::select! {
                next = queued.recv() => match next {
                    Some(bytes) => {
                        if send.write_all(&bytes).await.is_err() {
                            break;
                        }
                    }
                    // The app ended it.
                    None => {
                        let _ = send.finish();
                        break;
                    }
                },
                read = recv.read(&mut buf), if reading => match read {
                    Ok(Some(n)) => {
                        if reads {
                            tokio::select! {
                                sent = arrived.send(buf[..n].to_vec()) => if sent.is_err() { break },
                                // Ended while the app had stopped reading.
                                _ = closed.notified() => break,
                            }
                        }
                    }
                    // A viewer that never sends may finish its half early:
                    // only a display, where this is the video, ends here.
                    Ok(None) if ends_with_input => break,
                    Ok(None) => reading = false,
                    Err(_) => break,
                },
            }
        }
        sessions().lock().unwrap().remove(&id);
        // Dropping the session reports `SessionEnded`.
        drop(session);
    });
}

fn handle(id: &str) -> Option<Arc<Handle>> {
    sessions().lock().unwrap().get(id).cloned()
}

/// Queues bytes for the other side. False once the session is gone: the
/// app's encoder or input should stop. Blocks while the queue is full, which
/// paces the encoder to the network.
pub(crate) fn write(id: &str, bytes: Vec<u8>) -> bool {
    let Some(out) = handle(id).and_then(|h| h.out.lock().unwrap().clone()) else { return false };
    out.blocking_send(bytes).is_ok()
}

/// [`write`] for async callers (Dart): waits for room instead of blocking.
pub(crate) async fn write_async(id: &str, bytes: Vec<u8>) -> bool {
    let Some(out) = handle(id).and_then(|h| h.out.lock().unwrap().clone()) else { return false };
    out.send(bytes).await.is_ok()
}

/// The next bytes from the other side, blocking; None once it's over.
pub(crate) fn read(id: &str) -> Option<Vec<u8>> {
    let h = handle(id)?;
    let mut slot = h.incoming.lock().unwrap();
    slot.as_mut()?.blocking_recv()
}

/// Ends this side; the core then reports `SessionEnded`. Closing the queue
/// ends the session's task, which also wakes a reader waiting in `read`.
pub(crate) fn end(id: &str) {
    if let Some(h) = sessions().lock().unwrap().remove(id) {
        h.out.lock().unwrap().take();
        h.closed.notify_one();
    }
}

#[cfg(target_os = "android")]
mod jni_api {
    use jni::JNIEnv;
    use jni::objects::{JByteArray, JClass, JString};
    use jni::sys::{JNI_FALSE, JNI_TRUE, jboolean, jbyteArray};

    fn id(env: &mut JNIEnv, id: &JString) -> Option<String> {
        env.get_string(id).ok().map(Into::into)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_media_NativeSession_write(
        mut env: JNIEnv,
        _this: JClass,
        session: JString,
        data: JByteArray,
    ) -> jboolean {
        let Some(session) = id(&mut env, &session) else { return JNI_FALSE };
        let Ok(bytes) = env.convert_byte_array(&data) else { return JNI_FALSE };
        if super::write(&session, bytes) { JNI_TRUE } else { JNI_FALSE }
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_media_NativeSession_read(
        mut env: JNIEnv,
        _this: JClass,
        session: JString,
    ) -> jbyteArray {
        let Some(session) = id(&mut env, &session) else { return std::ptr::null_mut() };
        match super::read(&session) {
            Some(bytes) => env.byte_array_from_slice(&bytes).map(|a| a.into_raw()).unwrap_or(std::ptr::null_mut()),
            None => std::ptr::null_mut(),
        }
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_media_NativeSession_finish(
        mut env: JNIEnv,
        _this: JClass,
        session: JString,
    ) {
        if let Some(session) = id(&mut env, &session) {
            super::end(&session);
        }
    }
}
