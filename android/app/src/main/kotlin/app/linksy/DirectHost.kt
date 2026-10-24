package app.linksy

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.net.Inet4Address
import java.net.NetworkInterface

/// This phone's side of a direct link (docs/protocol.md §4.17): a Wi-Fi Direct group of
/// its own that a computer joins for big transfers. The core relays the steps; this does
/// the Wi-Fi part and reports each step through [step]: `invite` (with `address`),
/// `connecting`, `up` (with `ip`), or `end` (with `reason`). One link at a time.
object DirectHost {
    /// Set by the app: (device id, step).
    @Volatile var step: ((String, Map<String, String>) -> Unit)? = null

    /// Set by the activity while it's in front: asks for [permission], then answers.
    @Volatile var ask: ((String, (Boolean) -> Unit) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var registeredOn: Context? = null

    /// The device the link is for, the computer's address once it listens, and how far it got.
    private var device: String? = null
    private var target: String? = null
    private var connecting = false
    private var up = false

    /// Whether this phone can host one: Wi-Fi Direct, and Android 10+ (`requestDeviceInfo`).
    fun supported(context: Context) =
        Build.VERSION.SDK_INT >= 29 && context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)

    private fun permission() =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION

    /// `DirectWanted`: start over, then invite the computer with this phone's address.
    fun want(context: Context, id: String) = main.post {
        val app = context.applicationContext
        if (device != null && device != id) {
            report(id, "end", "reason" to "already linked to another device")
            return@post
        }
        if (!supported(app)) return@post report(id, "end", "reason" to "no Wi-Fi Direct on this phone")
        val wifi = app.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) return@post report(id, "end", "reason" to "Wi-Fi is off")
        val permission = permission()
        if (app.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            begin(app, id)
            return@post
        }
        // Asked once, in front only: a refusal stays a refusal, the transfer goes the usual way
        val prefs = app.getSharedPreferences("permissions", Context.MODE_PRIVATE)
        val asking = ask
        if (asking == null || prefs.getBoolean(permission, false)) {
            return@post report(id, "end", "reason" to "no Wi-Fi Direct permission")
        }
        prefs.edit().putBoolean(permission, true).apply()
        asking(permission) { granted ->
            main.post { if (granted) begin(app, id) else report(id, "end", "reason" to "no Wi-Fi Direct permission") }
        }
    }

    @SuppressLint("MissingPermission")
    private fun begin(context: Context, id: String) {
        stop()
        device = id
        val manager = context.getSystemService(WifiP2pManager::class.java)
            ?: return fail("no Wi-Fi Direct on this phone")
        val channel = manager.initialize(context, Looper.getMainLooper()) { fail("Wi-Fi Direct stopped") }
        this.manager = manager
        this.channel = channel
        listen(context)
        // Anything left over from before goes first
        manager.removeGroup(channel, null)
        manager.requestDeviceInfo(channel) { info ->
            val address = info?.deviceAddress
            if (address == null || device != id) return@requestDeviceInfo fail("this phone's Wi-Fi Direct address is unknown")
            manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = report(id, "invite", "address" to address.lowercase())
                override fun onFailure(reason: Int) = fail("couldn't look for the computer (${why(reason)})")
            })
        }
    }

    /// `listening`: connect once the computer shows up among the peers.
    fun listening(id: String, address: String) = main.post {
        if (device != id) return@post
        target = address.lowercase()
        lookForTarget()
    }

    @SuppressLint("MissingPermission")
    private fun lookForTarget() {
        val (manager, channel, address) = Triple(manager ?: return, channel ?: return, target ?: return)
        if (connecting) return
        manager.requestPeers(channel) { peers ->
            if (connecting || target != address) return@requestPeers
            if (peers.deviceList.none { it.deviceAddress.equals(address, ignoreCase = true) }) return@requestPeers
            connecting = true
            val config = WifiP2pConfig().apply {
                deviceAddress = address
                wps.setup = WpsInfo.PBC
                groupOwnerIntent = 15
            }
            connect(manager, channel, config, tries = 3)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(manager: WifiP2pManager, channel: WifiP2pManager.Channel, config: WifiP2pConfig, tries: Int) {
        val id = device ?: return
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = report(id, "connecting")
            override fun onFailure(reason: Int) {
                // Busy for a moment (still discovering): again shortly
                if (tries > 1 && device == id) {
                    main.postDelayed({ connect(manager, channel, config, tries - 1) }, 1000)
                } else {
                    fail("couldn't connect to the computer (${why(reason)})")
                }
            }
        })
    }

    private fun listen(context: Context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> lookForTarget()
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> checkGroup()
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION ->
                        if (intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, 0) == WifiP2pManager.WIFI_P2P_STATE_DISABLED) {
                            fail("Wi-Fi is off")
                        }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
        this.receiver = receiver
        registeredOn = context
    }

    private fun checkGroup() {
        val (manager, channel, id) = Triple(manager ?: return, channel ?: return, device ?: return)
        manager.requestConnectionInfo(channel) { info ->
            if (up || device != id || info == null || !info.groupFormed) return@requestConnectionInfo
            val ip = if (info.isGroupOwner) info.groupOwnerAddress?.hostAddress else p2pAddress()
            if (ip == null) return@requestConnectionInfo fail("no address on the direct link")
            up = true
            report(id, "up", "ip" to ip)
        }
    }

    /// This phone's IPv4 address on its Wi-Fi Direct interface (`p2p…`), when it isn't the owner.
    private fun p2pAddress(): String? = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.name.startsWith("p2p") && it.isUp }
            .flatMap { it.inetAddresses.toList() }
            .firstOrNull { it is Inet4Address }?.hostAddress
    }.getOrNull()

    /// `DirectEnded`: drop the group and everything else.
    fun ended(id: String) = main.post { if (device == id) stop() }

    private fun fail(reason: String) {
        val id = device ?: return
        stop()
        report(id, "end", "reason" to reason)
    }

    private fun stop() {
        val (manager, channel) = manager to channel
        if (manager != null && channel != null) {
            manager.stopPeerDiscovery(channel, null)
            manager.removeGroup(channel, null)
            if (Build.VERSION.SDK_INT >= 27) channel.close()
        }
        receiver?.let { r -> runCatching { registeredOn?.unregisterReceiver(r) } }
        receiver = null
        registeredOn = null
        this.manager = null
        this.channel = null
        device = null
        target = null
        connecting = false
        up = false
    }

    private fun report(id: String, type: String, vararg extra: Pair<String, String>) {
        val step = this.step ?: return
        main.post { step(id, mapOf("type" to type) + extra) }
    }

    private fun why(reason: Int) = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "unsupported"
        WifiP2pManager.BUSY -> "busy"
        else -> "error $reason"
    }
}
