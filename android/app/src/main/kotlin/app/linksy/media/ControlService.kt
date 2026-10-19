package app.linksy.media

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/// Performs a computer's taps, swipes and keys on this phone during a
/// `control` session (docs/protocol.md §7). The user turns it on once in
/// Settings → Accessibility; until then control requests are declined as
/// unsupported. It acts only when a session hands it input.
class ControlService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    companion object {
        @Volatile var instance: ControlService? = null
            private set

        /// Whether the user turned the service on in Accessibility settings.
        fun enabled(context: Context): Boolean {
            val me = ComponentName(context, ControlService::class.java).flattenToString()
            val on = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            return on?.split(':')?.any { it.equals(me, ignoreCase = true) } == true
        }
    }
}
