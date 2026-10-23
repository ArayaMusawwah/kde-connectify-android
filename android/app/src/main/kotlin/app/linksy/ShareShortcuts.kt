package app.linksy

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import java.io.File

/// Each paired device in Android's share sheet, like a contact (issue #10):
/// one sharing shortcut per device, most recently used first, matched by the
/// `<share-target>` in res/xml/shortcuts.xml. Picking one starts [ShareTarget]
/// with the shortcut's id, and the share goes straight to that device.
object ShareShortcuts {
    private const val CATEGORY = "app.linksy.category.SHARE_TARGET"
    private const val PREFIX = "device:"
    private const val SIZE = 192

    /// The device a share was aimed at, if it came through one of ours.
    fun deviceOf(intent: Intent): String? {
        if (Build.VERSION.SDK_INT < 29) return null
        return intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)
            ?.takeIf { it.startsWith(PREFIX) }?.removePrefix(PREFIX)
    }

    /// Replaces the shortcuts with [devices] (`id`, `name`, `initials`, and
    /// `picture`, a path or null), in order: the first is shown first.
    fun update(context: Context, devices: List<Map<String, String?>>) {
        if (Build.VERSION.SDK_INT < 29) return
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val shortcuts = devices.take(manager.maxShortcutCountPerActivity).mapIndexed { rank, d ->
            val id = d["id"]!!
            val name = d["name"] ?: id
            ShortcutInfo.Builder(context, PREFIX + id)
                .setShortLabel(name)
                .setLongLabel(name)
                .setIcon(Icon.createWithBitmap(d["picture"]?.let(::round) ?: initials(d["initials"] ?: "")))
                .setCategories(setOf(CATEGORY))
                // From the launcher's menu it just opens the app.
                .setIntent(Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN))
                .setRank(rank)
                .apply { if (Build.VERSION.SDK_INT >= 30) setLongLived(true) }
                .build()
        }
        runCatching {
            // Gone devices go from the share sheet too.
            val gone = manager.dynamicShortcuts.map { it.id }.filter { old -> shortcuts.none { it.id == old } }
            if (gone.isNotEmpty()) manager.removeLongLivedShortcuts(gone)
            manager.dynamicShortcuts = shortcuts
        }.onFailure { Log.w("linksy", "share shortcuts not updated ($it)") }
    }

    /// A share went to [device]: Android ranks it higher.
    fun used(context: Context, device: String) {
        if (Build.VERSION.SDK_INT < 29) return
        context.getSystemService(ShortcutManager::class.java)?.reportShortcutUsed(PREFIX + device)
    }

    /// The device's picture, round.
    private fun round(path: String): Bitmap? {
        val file = File(path)
        if (!file.isFile) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= SIZE) sample *= 2
        val source = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val side = minOf(source.width, source.height)
        val square = Bitmap.createBitmap(source, (source.width - side) / 2, (source.height - side) / 2, side, side)
        val scaled = Bitmap.createScaledBitmap(square, SIZE, SIZE, true)
        val out = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
        Canvas(out).drawCircle(SIZE / 2f, SIZE / 2f, SIZE / 2f, paint)
        return out
    }

    /// No picture: the device's initials on Linksy's blue, as in the app.
    private fun initials(text: String): Bitmap {
        val out = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawCircle(SIZE / 2f, SIZE / 2f, SIZE / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(0x25, 0x63, 0xFF) })
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = SIZE * 0.38f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(text, SIZE / 2f, SIZE / 2f - (paint.descent() + paint.ascent()) / 2, paint)
        return out
    }
}
