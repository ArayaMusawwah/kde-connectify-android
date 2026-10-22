package app.linksy

import android.content.Context
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.DataInputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketAddress

/// The USB cable to a computer (docs/protocol.md §4.11): the computer switched the
/// phone into accessory mode, and Linksy's own QUIC packets cross the cable,
/// each as a 2-byte big-endian length and the UDP payload. Here, a UDP socket
/// on 127.0.0.1 stands in for the computer: the node dials it like any
/// address, and every datagram goes over the cable and back.
class UsbBridge private constructor(
    private val accessory: UsbAccessory,
    private val fd: ParcelFileDescriptor,
    private val onClosed: () -> Unit,
) {
    private val socket = DatagramSocket(InetSocketAddress(InetAddress.getLoopbackAddress(), 0))
    private val input = DataInputStream(FileInputStream(fd.fileDescriptor).buffered(64 * 1024))
    private val output = FileOutputStream(fd.fileDescriptor)

    /// The node's own address, learned from its first datagram.
    @Volatile private var node: SocketAddress? = null
    @Volatile private var closed = false

    /// Where the node dials the computer through the cable.
    val port: Int get() = socket.localPort

    init {
        Thread(::toCable, "linksy-usb-out").apply { isDaemon = true; start() }
        Thread(::fromCable, "linksy-usb-in").apply { isDaemon = true; start() }
    }

    private fun toCable() {
        val buf = ByteArray(65_535)
        val packet = DatagramPacket(buf, buf.size)
        // Frames waiting together go out in one write.
        val batch = java.io.ByteArrayOutputStream(16 * 1024)
        try {
            while (!closed) {
                packet.setData(buf)
                socket.receive(packet)
                node = packet.socketAddress
                batch.reset()
                frame(batch, packet)
                socket.soTimeout = 1
                try {
                    while (batch.size() < 32 * 1024) {
                        packet.setData(buf)
                        socket.receive(packet)
                        frame(batch, packet)
                    }
                } catch (_: java.net.SocketTimeoutException) {
                    // Nothing more waiting.
                } finally {
                    socket.soTimeout = 0
                }
                output.write(batch.toByteArray())
            }
        } catch (e: Exception) {
            if (!closed) Log.i("linksy", "usb cable: out ended ($e)")
        }
        close()
    }

    private fun frame(out: java.io.ByteArrayOutputStream, packet: DatagramPacket) {
        val n = packet.length
        out.write(n ushr 8)
        out.write(n and 0xff)
        out.write(packet.data, packet.offset, n)
    }

    private fun fromCable() {
        val buf = ByteArray(65_535)
        try {
            while (!closed) {
                val n = input.readUnsignedShort()
                input.readFully(buf, 0, n)
                val to = node ?: continue
                socket.send(DatagramPacket(buf, n, to))
            }
        } catch (e: Exception) {
            if (!closed) Log.i("linksy", "usb cable: in ended ($e)")
        }
        close()
    }

    fun close() {
        if (closed) return
        closed = true
        runCatching { socket.close() }
        runCatching { fd.close() }
        if (current === this) current = null
        onClosed()
    }

    companion object {
        /// The bridge for the cable plugged in now, if any.
        @Volatile var current: UsbBridge? = null
            private set

        fun isLinksy(accessory: UsbAccessory) =
            accessory.manufacturer == "Linksy" && accessory.model == "Linksy"

        /// Asked for and not answered yet: one dialog at a time.
        @Volatile private var asking: UsbAccessory? = null
        /// Refused: not asked again until it's plugged in again.
        @Volatile private var refused: UsbAccessory? = null

        const val ACTION_PERMISSION = "app.linksy.USB_PERMISSION"

        /// Opens [accessory]; returns the bridge's port, or null. Without
        /// permission (no "open with" prompt was shown or answered, as on
        /// realme/ColorOS) it asks, and [ACTION_PERMISSION] comes back.
        fun open(context: Context, accessory: UsbAccessory, onClosed: () -> Unit = {}): Int? {
            if (!isLinksy(accessory)) return null
            current?.let { if (it.accessory == accessory) return it.port; it.close() }
            val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            if (!manager.hasPermission(accessory)) {
                if (asking != accessory && refused != accessory) {
                    asking = accessory
                    Log.i("linksy", "usb cable: asking permission")
                    val intent = android.content.Intent(ACTION_PERMISSION).setPackage(context.packageName)
                    val flags = if (android.os.Build.VERSION.SDK_INT >= 31) android.app.PendingIntent.FLAG_MUTABLE else 0
                    manager.requestPermission(accessory, android.app.PendingIntent.getBroadcast(context, 0, intent, flags))
                }
                return null
            }
            asking = null
            val fd = runCatching { manager.openAccessory(accessory) }
                .onFailure { Log.w("linksy", "usb cable: open failed ($it)") }
                .getOrNull()
            if (fd == null) {
                Log.w("linksy", "usb cable: openAccessory gave nothing")
                return null
            }
            return runCatching { UsbBridge(accessory, fd, onClosed) }
                .onFailure { Log.w("linksy", "usb cable: bridge failed ($it)") }
                .getOrNull()?.also {
                    current = it
                    Log.i("linksy", "usb cable: bridge on 127.0.0.1:${it.port}")
                }?.port
        }

        /// The permission dialog was answered.
        fun answered(granted: Boolean) {
            if (!granted) refused = asking
            asking = null
        }

        /// An accessory already attached (the app opened by other means, or
        /// Android never sent the intent).
        fun openAttached(context: Context, onClosed: () -> Unit = {}): Int? {
            val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            val accessory = manager.accessoryList?.firstOrNull(::isLinksy) ?: return null
            return open(context, accessory, onClosed)
        }

        /// The cable came out.
        fun detached() {
            asking = null
            refused = null
            current?.close()
        }
    }
}
