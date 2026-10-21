package app.linksy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/// "fedora wants to send you 3 files" as a notification with Accept and
/// Decline, for when Linksy isn't on screen. The buttons answer through
/// [answer], which the running app sets.
object TransferNotice {
    private const val CHANNEL = "incoming"
    private const val ACTION = "app.linksy.TRANSFER_ANSWER"

    /// Set by the app while it can answer: (transfer, accept).
    @Volatile var answer: ((String, Boolean) -> Unit)? = null

    fun post(context: Context, transfer: String, title: String, body: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Incoming files", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        fun button(accept: Boolean) = PendingIntent.getBroadcast(
            context, transfer.hashCode() * 2 + if (accept) 1 else 0,
            Intent(context, Answer::class.java).setAction(ACTION).putExtra("transfer", transfer).putExtra("accept", accept),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val open = PendingIntent.getActivity(
            context, transfer.hashCode(), Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        val note = builder
            .setSmallIcon(R.drawable.ic_stat_linksy)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setTimeoutAfter(120_000) // the request expires then anyway
            .addAction(Notification.Action.Builder(null, "Accept", button(true)).build())
            .addAction(Notification.Action.Builder(null, "Decline", button(false)).build())
            .build()
        runCatching { manager.notify(transfer.hashCode(), note) }
    }

    fun cancel(context: Context, transfer: String) {
        context.getSystemService(NotificationManager::class.java).cancel(transfer.hashCode())
    }

    class Answer : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val transfer = intent.getStringExtra("transfer") ?: return
            cancel(context, transfer)
            answer?.invoke(transfer, intent.getBooleanExtra("accept", false))
        }
    }
}
