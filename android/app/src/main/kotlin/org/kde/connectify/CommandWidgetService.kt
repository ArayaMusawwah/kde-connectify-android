package org.kde.connectify

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class CommandWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CommandRemoteViewsFactory(applicationContext)
    }
}

class CommandRemoteViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private data class Item(val key: String, val name: String, val command: String)
    private val items = mutableListOf<Item>()
    private var deviceId: String = ""

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    private fun loadData() {
        items.clear()
        val prefs = context.getSharedPreferences("commands_cache", Context.MODE_PRIVATE)
        deviceId = prefs.getString("device_id", "") ?: ""
        val json = prefs.getString("commands_json", "[]") ?: "[]"
        try {
            val arr = JSONArray(json)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                items.add(
                    Item(
                        key = obj.optString("key"),
                        name = obj.optString("name"),
                        command = obj.optString("command")
                    )
                )
            }
        } catch (e: Exception) {
            // ignore
        }
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position !in items.indices) return null
        val item = items[position]

        val views = RemoteViews(context.packageName, R.layout.widget_command_item)
        views.setTextViewText(R.id.item_command_name, item.name)
        views.setTextViewText(R.id.item_command_script, item.command)

        val fillInIntent = Intent().apply {
            putExtra(CommandWidgetProvider.EXTRA_DEVICE_ID, deviceId)
            putExtra(CommandWidgetProvider.EXTRA_COMMAND_KEY, item.key)
            putExtra(CommandWidgetProvider.EXTRA_COMMAND_NAME, item.name)
        }
        views.setOnClickFillInIntent(R.id.widget_item_root, fillInIntent)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
