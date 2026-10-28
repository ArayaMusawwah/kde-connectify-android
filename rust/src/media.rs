//! Direct JNI bridge for broadcasting phone media player states over QUIC.

#[cfg(target_os = "android")]
mod jni_api {
    use jni::JNIEnv;
    use jni::objects::{JClass, JString};
    use jni::sys::{jboolean, JNI_FALSE, JNI_TRUE};

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_org_kde_connectify_NativeMedia_broadcastMediaState(
        mut env: JNIEnv,
        _this: JClass,
        state_json: JString,
    ) -> jboolean {
        let Some(json_str) = env.get_string(&state_json).ok().map(Into::<String>::into) else {
            return JNI_FALSE;
        };
        let Ok(state) = serde_json::from_str::<linksy_core::MediaState>(&json_str) else {
            return JNI_FALSE;
        };
        let Some(node) = crate::api::node::running() else {
            return JNI_FALSE;
        };
        crate::api::node::rt().spawn(async move {
            let devices = node.devices();
            for d in devices {
                if d.connected {
                    let _ = node.send_media_state(&d.device.id, &state).await;
                }
            }
        });
        JNI_TRUE
    }
}
