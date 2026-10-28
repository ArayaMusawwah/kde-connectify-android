package org.kde.connectify

object NativeMedia {
    init {
        System.loadLibrary("linksy_bridge")
    }

    external fun broadcastMediaState(stateJson: String): Boolean
}
