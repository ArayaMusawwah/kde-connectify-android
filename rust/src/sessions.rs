//! Accepted media sessions this phone shares into (its screen or camera), by
//! id. Android's encoders write H.264 into them straight through JNI
//! (`app.linksy.media.NativeSession`), not through Dart.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use linksy_core::{Node, Session};
use tokio::sync::Mutex as AsyncMutex;

use crate::api::node::rt;

type Shared = Arc<AsyncMutex<Session>>;

fn sessions() -> &'static Mutex<HashMap<String, Shared>> {
    static MAP: OnceLock<Mutex<HashMap<String, Shared>>> = OnceLock::new();
    MAP.get_or_init(Default::default)
}

/// Keeps every session the user accepted until it's written to or ended.
pub(crate) fn collect(node: &Node) {
    let Some(mut incoming) = node.incoming_sessions() else { return };
    rt().spawn(async move {
        while let Some(session) = incoming.recv().await {
            // Only sharing sessions (screen, camera) are accepted on the phone.
            if !session.sharing {
                continue;
            }
            let id = session.id.to_string();
            sessions().lock().unwrap().insert(id, Arc::new(AsyncMutex::new(session)));
        }
    });
}

/// Writes encoded video. False once the session is gone (the viewer stopped
/// or the connection dropped): the encoder should stop.
pub(crate) fn write(id: &str, bytes: &[u8]) -> bool {
    let Some(session) = sessions().lock().unwrap().get(id).cloned() else { return false };
    let ok = rt().block_on(async { session.lock().await.send.write_all(bytes).await.is_ok() });
    if !ok {
        end(id);
    }
    ok
}

/// Finishes this side of the stream and drops the session (the core then
/// reports `SessionEnded`).
pub(crate) fn end(id: &str) {
    let Some(session) = sessions().lock().unwrap().remove(id) else { return };
    rt().spawn(async move {
        let _ = session.lock().await.send.finish();
    });
}

#[cfg(target_os = "android")]
mod jni_api {
    use jni::JNIEnv;
    use jni::objects::{JByteArray, JClass, JString};
    use jni::sys::{JNI_FALSE, JNI_TRUE, jboolean};

    fn id(env: &mut JNIEnv, id: &JString) -> Option<String> {
        env.get_string(id).ok().map(Into::into)
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_media_NativeSession_write(
        mut env: JNIEnv,
        _class: JClass,
        session: JString,
        data: JByteArray,
    ) -> jboolean {
        let Some(session) = id(&mut env, &session) else { return JNI_FALSE };
        let Ok(bytes) = env.convert_byte_array(&data) else { return JNI_FALSE };
        if super::write(&session, &bytes) { JNI_TRUE } else { JNI_FALSE }
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_media_NativeSession_finish(
        mut env: JNIEnv,
        _class: JClass,
        session: JString,
    ) {
        if let Some(session) = id(&mut env, &session) {
            super::end(&session);
        }
    }
}
