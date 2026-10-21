//! Serving this phone's files to a computer ("phone in the Files sidebar",
//! docs/protocol.md §4.9). Android's side (`app.linksy.files.FileServer`) answers
//! through JNI, pulling one request at a time as sessions do: Rust never calls
//! into Java. While sharing is off, requests are turned down here.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use linksy_core::fs::FsCall;
use linksy_core::{FsEntry, Node};
use tokio::sync::mpsc;

use crate::api::node::rt;

static SHARING: AtomicBool = AtomicBool::new(false);

struct Queue {
    tx: mpsc::UnboundedSender<u64>,
    rx: Mutex<mpsc::UnboundedReceiver<u64>>,
}

fn queue() -> &'static Queue {
    static Q: OnceLock<Queue> = OnceLock::new();
    Q.get_or_init(|| {
        let (tx, rx) = mpsc::unbounded_channel();
        Queue { tx, rx: Mutex::new(rx) }
    })
}

/// Requests waiting for Android's answer, by number.
fn calls() -> &'static Mutex<HashMap<u64, FsCall>> {
    static MAP: OnceLock<Mutex<HashMap<u64, FsCall>>> = OnceLock::new();
    MAP.get_or_init(Default::default)
}

/// Turns sharing on or off (the app's switch, with a folder chosen).
pub(crate) fn set_sharing(on: bool) {
    SHARING.store(on, Ordering::SeqCst);
}

/// Takes every file request this node gets, for its lifetime.
pub(crate) fn collect(node: &Node) {
    let Some(mut incoming) = node.incoming_fs() else { return };
    rt().spawn(async move {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        while let Some(call) = incoming.recv().await {
            if !SHARING.load(Ordering::SeqCst) {
                let _ = call
                    .error("This phone doesn't share its files. Turn on file sharing in Linksy on the phone.", false)
                    .await;
                continue;
            }
            let n = NEXT.fetch_add(1, Ordering::Relaxed);
            calls().lock().unwrap().insert(n, call);
            let _ = queue().tx.send(n);
        }
    });
}

/// The next request as JSON (`{"id":n,"from":"name","op":"list","path":…}`),
/// blocking until there is one.
pub(crate) fn next() -> Option<String> {
    loop {
        let n = queue().rx.lock().unwrap().blocking_recv()?;
        let map = calls().lock().unwrap();
        let Some(call) = map.get(&n) else { continue };
        let mut j = serde_json::to_value(&call.request).ok()?;
        j["id"] = n.into();
        j["from"] = call.from.name.clone().into();
        return Some(j.to_string());
    }
}

/// A write's bytes, read from the request's stream.
pub(crate) fn body(n: u64) -> Option<Vec<u8>> {
    let mut call = calls().lock().unwrap().remove(&n)?;
    let bytes = rt().block_on(call.body()).ok();
    calls().lock().unwrap().insert(n, call);
    bytes
}

/// What Android answers (JSON, the core's `FsReply` shape), then `data` for a read.
pub(crate) fn reply(n: u64, json: &str, data: Vec<u8>) {
    let Some(call) = calls().lock().unwrap().remove(&n) else { return };
    let value: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    rt().spawn(async move {
        let result = match value["type"].as_str() {
            Some("fs_entries") => {
                let entries: Vec<FsEntry> = serde_json::from_value(value["entries"].clone()).unwrap_or_default();
                call.entries(entries).await
            }
            Some("fs_entry") => match serde_json::from_value::<FsEntry>(value["entry"].clone()) {
                Ok(entry) => call.entry(entry).await,
                Err(_) => call.error("bad entry", false).await,
            },
            Some("fs_data") => call.data(&data).await,
            Some("fs_info") => call.info(value["name"].as_str().unwrap_or("")).await,
            Some("fs_ok") => call.ok().await,
            _ => {
                let message = value["message"].as_str().unwrap_or("That didn't work on the phone.");
                call.error(message, value["not_found"].as_bool().unwrap_or(false)).await
            }
        };
        if let Err(e) = result {
            tracing::debug!(error = %e, "file answer didn't go out");
        }
    });
}

#[cfg(target_os = "android")]
mod jni_api {
    use jni::JNIEnv;
    use jni::objects::{JByteArray, JClass, JString};
    use jni::sys::{jboolean, jbyteArray, jlong, jstring};

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_files_NativeFiles_next(env: JNIEnv, _this: JClass) -> jstring {
        match super::next() {
            Some(s) => env.new_string(s).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut()),
            None => std::ptr::null_mut(),
        }
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_files_NativeFiles_body(env: JNIEnv, _this: JClass, id: jlong) -> jbyteArray {
        match super::body(id as u64) {
            Some(b) => env.byte_array_from_slice(&b).map(|a| a.into_raw()).unwrap_or(std::ptr::null_mut()),
            None => std::ptr::null_mut(),
        }
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_files_NativeFiles_reply(
        mut env: JNIEnv,
        _this: JClass,
        id: jlong,
        json: JString,
        data: JByteArray,
    ) {
        let json: String = env.get_string(&json).map(Into::into).unwrap_or_default();
        let data = if data.is_null() { Vec::new() } else { env.convert_byte_array(&data).unwrap_or_default() };
        super::reply(id as u64, &json, data);
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_app_linksy_files_NativeFiles_sharing(_env: JNIEnv, _this: JClass, on: jboolean) {
        super::set_sharing(on != 0);
    }
}
