//! `linksy_core::Node` for Dart. Values cross as JSON in the core's own serde
//! shapes (the same as the desktop IPC), so the Dart side parses one format
//! and this file stays thin. Errors cross as `kind` or `kind:message`, for
//! the app to word with the device's name.

use std::future::Future;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::OnceLock;

use flutter_rust_bridge::frb;
use linksy_core::{Config, DeviceKind, Error, Fingerprint, Node, Settings, Uuid};
use tokio::runtime::Runtime;
use tokio::sync::broadcast::error::RecvError;

use crate::frb_generated::StreamSink;

/// The core spawns its tasks on tokio; it gets a runtime of its own.
pub(crate) fn rt() -> &'static Runtime {
    static RT: OnceLock<Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("linksy")
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

async fn run<T: Send + 'static>(f: impl Future<Output = Result<T, Error>> + Send + 'static) -> Result<T, String> {
    rt().spawn(f).await.map_err(|e| format!("other:{e}"))?.map_err(kind)
}

fn kind(e: Error) -> String {
    match e {
        Error::Unreachable => "unreachable".into(),
        Error::Declined => "declined".into(),
        Error::Timeout => "timeout".into(),
        Error::NotPaired => "not_paired".into(),
        Error::Invalid(m) => format!("invalid:{m}"),
        other => format!("other:{other}"),
    }
}

fn fingerprint(id: &str) -> Result<Fingerprint, String> {
    id.parse().map_err(|_| "invalid:That isn't a Linksy device id.".to_string())
}

fn json<T: serde::Serialize>(v: &T) -> String {
    serde_json::to_string(v).unwrap_or_default()
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // That sets up logging at trace level: mDNS alone floods logcat.
    log::set_max_level(log::LevelFilter::Info);
    #[cfg(target_os = "android")]
    {
        use tracing_subscriber::filter::LevelFilter;
        use tracing_subscriber::prelude::*;
        let _ = tracing_subscriber::registry()
            .with(paranoid_android::layer("linksy").with_filter(LevelFilter::INFO))
            .try_init();
    }
}

#[frb(opaque)]
pub struct LinksyNode {
    node: Node,
}

/// Starts this phone's node. Identity, paired devices and settings live in
/// `data_dir` (app-private). Prefers the desktop's port 47200 and mDNS; falls
/// back to a free port, then to no discovery, rather than not starting.
pub async fn start_node(data_dir: String, download_dir: String, name: String) -> Result<LinksyNode, String> {
    let mut last = String::new();
    for (port, discovery) in [(47200, true), (0, true), (47200, false), (0, false)] {
        let mut config = Config::new(PathBuf::from(&data_dir), PathBuf::from(&download_dir), name.clone());
        config.kind = DeviceKind::Phone;
        config.port = port;
        config.discovery = discovery;
        match run(Node::start(config)).await {
            Ok(node) => {
                crate::sessions::collect(&node);
                return Ok(LinksyNode { node });
            }
            Err(e) => {
                tracing::warn!(port, discovery, error = %e, "node didn't start, trying the next way");
                last = e;
            }
        }
    }
    Err(last)
}

impl LinksyNode {
    /// This device, as `DeviceInfo` JSON.
    #[frb(sync)]
    pub fn info_json(&self) -> String {
        json(&self.node.info())
    }

    /// Every known device, as a JSON list of `DeviceView`.
    #[frb(sync)]
    pub fn devices_json(&self) -> String {
        json(&self.node.devices())
    }

    #[frb(sync)]
    pub fn settings_json(&self) -> String {
        json(&self.node.settings())
    }

    /// The port this node listens on, for "pair by address" from elsewhere.
    #[frb(sync)]
    pub fn port(&self) -> u16 {
        self.node.local_addr().map(|a| a.port()).unwrap_or(0)
    }

    /// Every core event as JSON (`{"type": "...", ...}`), until the app stops
    /// listening.
    pub fn events(&self, sink: StreamSink<String>) {
        let mut rx = self.node.subscribe();
        rt().spawn(async move {
            loop {
                match rx.recv().await {
                    Ok(event) => {
                        if sink.add(json(&event)).is_err() {
                            break;
                        }
                    }
                    Err(RecvError::Lagged(n)) => tracing::warn!(n, "app fell behind on events"),
                    Err(RecvError::Closed) => break,
                }
            }
        });
    }

    pub async fn update_settings(&self, settings_json: String) -> Result<(), String> {
        let settings: Settings = serde_json::from_str(&settings_json).map_err(|e| format!("other:{e}"))?;
        let node = self.node.clone();
        run(async move { node.update_settings(settings).await.map(|_| ()) }).await
    }

    pub async fn pair_device(&self, id: String) -> Result<(), String> {
        let id = fingerprint(&id)?;
        let node = self.node.clone();
        run(async move { node.pair_device(id).await.map(|_| ()) }).await
    }

    /// `ip:port` or `[ipv6]:port`.
    pub async fn pair_address(&self, address: String) -> Result<(), String> {
        let addr: SocketAddr = address
            .trim()
            .parse()
            .map_err(|_| "invalid:That address doesn't look right. Use the form 192.168.1.20:47200.".to_string())?;
        let node = self.node.clone();
        run(async move { node.pair(addr).await.map(|_| ()) }).await
    }

    /// A scanned `linksy://pair?…` link.
    pub async fn pair_with_invite(&self, uri: String) -> Result<(), String> {
        let node = self.node.clone();
        run(async move { node.pair_with_invite(&uri).await.map(|_| ()) }).await
    }

    /// Answer a pairing or transfer request. False if it already expired.
    #[frb(sync)]
    pub fn respond(&self, request: String, accept: bool) -> bool {
        Uuid::parse_str(&request).is_ok_and(|id| self.node.respond(id, accept))
    }

    /// Returns the transfer id.
    pub async fn send_files(&self, id: String, paths: Vec<String>) -> Result<String, String> {
        let id = fingerprint(&id)?;
        let node = self.node.clone();
        let paths = paths.into_iter().map(PathBuf::from).collect();
        run(async move { node.send_files(&id, paths).await.map(|t| t.to_string()) }).await
    }

    #[frb(sync)]
    pub fn cancel(&self, transfer: String) -> bool {
        Uuid::parse_str(&transfer).is_ok_and(|id| self.node.cancel(id))
    }

    pub async fn send_clipboard(&self, id: String, text: String) -> Result<(), String> {
        let id = fingerprint(&id)?;
        let node = self.node.clone();
        run(async move { node.send_clipboard(&id, &text).await }).await
    }

    pub async fn notify(&self, id: String, title: String, body: String) -> Result<(), String> {
        let id = fingerprint(&id)?;
        let node = self.node.clone();
        run(async move { node.notify(&id, &title, &body).await }).await
    }

    #[frb(sync)]
    pub fn forget(&self, id: String) -> Result<(), String> {
        let id = fingerprint(&id)?;
        self.node.forget(&id).map(|_| ()).map_err(kind)
    }

    /// Stops sharing into a session (the Stop button, or the encoder ended).
    #[frb(sync)]
    pub fn end_session(&self, session: String) {
        crate::sessions::end(&session);
    }

    pub async fn shutdown(&self) -> Result<(), String> {
        let node = self.node.clone();
        run(async move {
            node.shutdown().await;
            Ok(())
        })
        .await
    }
}
