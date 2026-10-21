package app.linksy

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/// Android's own text (notifications, refusals sent to computers) in the
/// language picked in Linksy (`app.language`), else the phone's.
object Lang {
    fun str(context: Context, id: Int, vararg args: Any): String {
        val code = context.getSharedPreferences("linksy", Context.MODE_PRIVATE).getString("app.language", null)
        val res = if (code == null) {
            context.resources
        } else {
            val config = Configuration(context.resources.configuration).apply { setLocale(Locale.forLanguageTag(code)) }
            context.createConfigurationContext(config).resources
        }
        return res.getString(id, *args)
    }
}
