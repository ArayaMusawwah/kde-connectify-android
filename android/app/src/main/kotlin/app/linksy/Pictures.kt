package app.linksy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.File
import kotlin.math.max

/// A picture for each paired device, chosen on this phone and kept in the
/// app's private files (pictures/<device id>.jpg), at most 1600 px.
object Pictures {
    private const val MAX = 1600

    private fun dir(context: Context) = File(context.filesDir, "pictures").apply { mkdirs() }

    fun file(context: Context, device: String) = File(dir(context), "${device.filter { it.isLetterOrDigit() }}.jpg")

    /// Every device's picture: id → path.
    fun all(context: Context): Map<String, String> =
        dir(context).listFiles()?.filter { it.extension == "jpg" }
            ?.associate { it.nameWithoutExtension to it.path }.orEmpty()

    /// Saves [uri] as [device]'s picture; returns its path.
    fun save(context: Context, device: String, uri: Uri): String? = runCatching {
        val bitmap = decode(context, uri)
        val out = file(context, device)
        val tmp = File(out.path + ".tmp")
        tmp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        tmp.renameTo(out)
        out.path
    }.getOrNull()

    fun remove(context: Context, device: String) {
        file(context, device).delete()
    }

    /// Downscaled while decoding, and upright (ImageDecoder reads the
    /// orientation; older Android shows it as stored).
    private fun decode(context: Context, uri: Uri): Bitmap {
        if (Build.VERSION.SDK_INT >= 28) {
            val source = ImageDecoder.createSource(context.contentResolver, uri)
            return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                val longest = max(info.size.width, info.size.height)
                if (longest > MAX) {
                    val scale = MAX.toDouble() / longest
                    decoder.setTargetSize((info.size.width * scale).toInt(), (info.size.height * scale).toInt())
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX) sample *= 2
        return context.contentResolver.openInputStream(uri)!!.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })!!
        }
    }
}
