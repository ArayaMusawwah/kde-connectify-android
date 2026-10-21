package app.linksy

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper

/// One fresh fix when a computer asks where this phone is (docs/protocol.md §4.14).
/// Nothing is kept and nothing tracks: a single answer, or why not.
object Locator {
    private const val TIMEOUT_MS = 20_000L
    /// A fix this recent is as good as a new one.
    private const val FRESH_MS = 60_000L

    fun fix(context: Context, done: (Map<String, Any?>) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        var answered = false
        fun answer(result: Map<String, Any?>) = main.post {
            if (!answered) {
                answered = true
                done(result)
            }
        }
        fun refuse(reason: String) = answer(mapOf("error" to reason))

        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED
        ) {
            return refuse("Linksy isn't allowed to use this phone's location").let {}
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val on = if (Build.VERSION.SDK_INT >= 28) manager.isLocationEnabled else
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) || manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        if (!on) return refuse("Location is off on this phone").let {}

        val providers = buildList {
            if (Build.VERSION.SDK_INT >= 31 && manager.isProviderEnabled(LocationManager.FUSED_PROVIDER)) add(LocationManager.FUSED_PROVIDER)
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) add(LocationManager.GPS_PROVIDER)
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) add(LocationManager.NETWORK_PROVIDER)
        }
        val recent = try {
            providers.mapNotNull { manager.getLastKnownLocation(it) }
                .filter { System.currentTimeMillis() - it.time < FRESH_MS }
                .minByOrNull { if (it.hasAccuracy()) it.accuracy else Float.MAX_VALUE }
        } catch (_: SecurityException) {
            null
        }
        if (recent != null) return answer(of(recent)).let {}
        val provider = providers.firstOrNull() ?: return refuse("Location is off on this phone").let {}

        val cancel = CancellationSignal()
        main.postDelayed({
            cancel.cancel()
            refuse("This phone couldn't find where it is in time")
        }, TIMEOUT_MS)
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                manager.getCurrentLocation(provider, cancel, context.mainExecutor) { location ->
                    if (location != null) answer(of(location))
                    else refuse("Open Linksy on the phone to share where it is")
                }
            } else {
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(provider, { location -> answer(of(location)) }, Looper.getMainLooper())
            }
        } catch (_: SecurityException) {
            refuse("Linksy isn't allowed to use this phone's location")
        } catch (_: IllegalArgumentException) {
            refuse("Location is off on this phone")
        }
    }

    private fun of(l: Location): Map<String, Any?> = mapOf(
        "lat" to l.latitude,
        "lon" to l.longitude,
        "accuracy" to if (l.hasAccuracy()) l.accuracy.toDouble() else null,
        "at" to l.time,
    )
}
