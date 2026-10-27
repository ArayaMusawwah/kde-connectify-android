package app.linksy

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/// Tells the core when this phone's networks change (docs/protocol.md §4.13,
/// "Switching networks"): a network comes, goes, or gets a new address. Android
/// doesn't let iroh see that by itself. At most once a second: a burst of changes
/// (leaving Wi-Fi, mobile data taking over) becomes a call at once and, if more
/// came meanwhile, one a second later.
class NetworkWatcher(context: Context, private val changed: () -> Unit) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var last = 0L
    private var pending = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = poke()
        override fun onLost(network: Network) = poke()
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) = poke()
    }

    fun start() {
        // Every network, local Wi-Fi without internet too
        val request = NetworkRequest.Builder()
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        runCatching { connectivity?.registerNetworkCallback(request, callback) }
    }

    fun stop() {
        runCatching { connectivity?.unregisterNetworkCallback(callback) }
        main.removeCallbacksAndMessages(null)
    }

    private fun poke() {
        main.post(::schedule)
    }

    private fun schedule() {
        if (pending) return
        val wait = last + 1000 - SystemClock.elapsedRealtime()
        pending = true
        main.postDelayed({
            pending = false
            last = SystemClock.elapsedRealtime()
            changed()
        }, wait.coerceAtLeast(0))
    }
}
