package org.kde.connectify

object NativeCommands {
    init {
        System.loadLibrary("linksy_bridge")
    }

    external fun runCommand(deviceId: String, key: String): Boolean
    external fun requestCommands(deviceId: String): Boolean
}
