package org.kde.connectify

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.Toast

class CommandWidgetProvider : AppWidgetProvider() {
    companion object {
        const val ACTION_RUN_COMMAND = "org.kde.connectify.ACTION_RUN_COMMAND"
        const val ACTION_REFRESH_WIDGET = "org.kde.connectify.ACTION_REFRESH_WIDGET"
        const val EXTRA_DEVICE_ID = "device_id"
        const val EXTRA_COMMAND_KEY = "command_key"
        const val EXTRA_COMMAND_NAME = "command_name"

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CommandWidgetProvider::class.java))
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_commands_list)
            for (id in ids) {
                updateAppWidget(context, manager, id)
            }
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val prefs = context.getSharedPreferences("commands_cache", Context.MODE_PRIVATE)
            val deviceId = prefs.getString("device_id", "") ?: ""
            val deviceName = prefs.getString("device_name", "KDE Connectify") ?: "KDE Connectify"

            val views = RemoteViews(context.packageName, R.layout.widget_commands)
            views.setTextViewText(R.id.widget_device_name, deviceName)

            // Service Intent for ListView
            val serviceIntent = Intent(context, CommandWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_commands_list, serviceIntent)
            views.setEmptyView(R.id.widget_commands_list, R.id.widget_empty_view)

            // Click template for individual items in ListView
            val itemClickIntent = Intent(context, CommandWidgetProvider::class.java).apply {
                action = ACTION_RUN_COMMAND
            }
            val pendingItemClick = PendingIntent.getBroadcast(
                context,
                0,
                itemClickIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            views.setPendingIntentTemplate(R.id.widget_commands_list, pendingItemClick)

            // Refresh button
            val refreshIntent = Intent(context, CommandWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_WIDGET
                putExtra(EXTRA_DEVICE_ID, deviceId)
            }
            val pendingRefresh = PendingIntent.getBroadcast(
                context,
                appWidgetId,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_refresh_btn, pendingRefresh)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, id)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_RUN_COMMAND -> {
                val deviceId = intent.getStringExtra(EXTRA_DEVICE_ID) ?: ""
                val commandKey = intent.getStringExtra(EXTRA_COMMAND_KEY) ?: ""
                val commandName = intent.getStringExtra(EXTRA_COMMAND_NAME) ?: "Command"

                if (deviceId.isNotEmpty() && commandKey.isNotEmpty()) {
                    NativeCommands.runCommand(deviceId, commandKey)
                    Toast.makeText(context, "Executing: $commandName", Toast.LENGTH_SHORT).show()
                }
            }
            ACTION_REFRESH_WIDGET -> {
                val deviceId = intent.getStringExtra(EXTRA_DEVICE_ID) ?: ""
                if (deviceId.isNotEmpty()) {
                    NativeCommands.requestCommands(deviceId)
                    Toast.makeText(context, "Refreshing commands...", Toast.LENGTH_SHORT).show()
                }
                updateAllWidgets(context)
            }
        }
    }
}
