//! Direct JNI bridge for executing commands on paired computers from Android widgets/background services.

#[cfg(target_os = "android")]
mod jni_api {
    use jni::JNIEnv;
    use jni::objects::{JClass, JString};
    use jni::sys::{jboolean, JNI_FALSE, JNI_TRUE};
    use std::str::FromStr;

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_org_kde_connectify_NativeCommands_runCommand(
        mut env: JNIEnv,
        _this: JClass,
        device_id: JString,
        key: JString,
    ) -> jboolean {
        let Some(dev_str) = env.get_string(&device_id).ok().map(Into::<String>::into) else {
            return JNI_FALSE;
        };
        let Some(key_str) = env.get_string(&key).ok().map(Into::<String>::into) else {
            return JNI_FALSE;
        };
        let Ok(fp) = linksy_core::Fingerprint::from_str(&dev_str) else {
            return JNI_FALSE;
        };
        let Some(node) = crate::api::node::running() else {
            return JNI_FALSE;
        };
        crate::api::node::rt().spawn(async move {
            let _ = node.run_command(&fp, &key_str).await;
        });
        JNI_TRUE
    }

    #[unsafe(no_mangle)]
    pub extern "system" fn Java_org_kde_connectify_NativeCommands_requestCommands(
        mut env: JNIEnv,
        _this: JClass,
        device_id: JString,
    ) -> jboolean {
        let Some(dev_str) = env.get_string(&device_id).ok().map(Into::<String>::into) else {
            return JNI_FALSE;
        };
        let Ok(fp) = linksy_core::Fingerprint::from_str(&dev_str) else {
            return JNI_FALSE;
        };
        let Some(node) = crate::api::node::running() else {
            return JNI_FALSE;
        };
        crate::api::node::rt().spawn(async move {
            let _ = node.request_commands(&fp).await;
        });
        JNI_TRUE
    }
}
