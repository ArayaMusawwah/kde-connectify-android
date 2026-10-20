//! "Lock when you walk away" (docs/protocol.md §4.5): a computer asks for a heartbeat
//! every few seconds with `heartbeat_watch`; this sends them from the core's
//! own runtime, so they keep going whatever the UI does. One schedule per
//! computer; a new watch replaces it.

use std::collections::HashMap;
use std::time::Duration;

use linksy_core::{Event, Fingerprint, Node};
use tokio::sync::broadcast::error::RecvError;
use tokio::task::JoinHandle;

use crate::api::node::rt;

pub(crate) fn run(node: &Node) {
    let node = node.clone();
    let mut events = node.subscribe();
    rt().spawn(async move {
        let mut beating: HashMap<Fingerprint, JoinHandle<()>> = HashMap::new();
        loop {
            match events.recv().await {
                Ok(Event::HeartbeatWatch { from, on, every_s }) => {
                    if let Some(old) = beating.remove(&from.id) {
                        old.abort();
                    }
                    if on {
                        let node = node.clone();
                        let every = Duration::from_secs(every_s.clamp(5, 20).into());
                        beating.insert(
                            from.id,
                            tokio::spawn(async move {
                                loop {
                                    if let Err(e) = node.heartbeat(&from.id).await {
                                        tracing::debug!(error = %e, "heartbeat to {} failed", from.name);
                                    }
                                    tokio::time::sleep(every).await;
                                }
                            }),
                        );
                    }
                }
                Ok(_) | Err(RecvError::Lagged(_)) => {}
                Err(RecvError::Closed) => break,
            }
        }
    });
}
