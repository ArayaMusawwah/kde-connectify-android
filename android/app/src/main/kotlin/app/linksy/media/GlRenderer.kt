package app.linksy.media

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/// Between the camera and the encoder: draws each camera frame turned by
/// [rotation] (clockwise, 0/90/180/270) into the stream's frame, fitted
/// (whole picture, bars at the sides) or filled (cropped), and the same
/// picture into the phone's preview. The stream keeps its size whatever the
/// rotation, so the computer's webcam never changes shape.
class GlRenderer(
    camera: android.util.Size,
    private val output: Surface,
    private val outW: Int,
    private val outH: Int,
) {
    private val thread = HandlerThread("linksy-gl").apply { start() }
    private val handler = Handler(thread.looper)
    private lateinit var display: EGLDisplay
    private lateinit var context: EGLContext
    private lateinit var config: EGLConfig
    private lateinit var encoderSurface: EGLSurface
    private var previewSurface: EGLSurface? = null
    private var program = 0
    private var texture = 0
    private lateinit var surfaceTexture: SurfaceTexture

    /// Where the camera draws.
    lateinit var input: Surface
        private set

    /// The size the camera delivers (its own shape, which may not be the
    /// stream's): the picture is fitted by it, never stretched.
    @Volatile private var camera = camera

    @Volatile var rotation = 0
    @Volatile var fill = false
    @Volatile private var stopped = false
    private val stMatrix = FloatArray(16)
    private val quad: FloatBuffer = ByteBuffer.allocateDirect(4 * 4 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

    init {
        val ready = java.util.concurrent.CountDownLatch(1)
        handler.post {
            setUp()
            ready.countDown()
        }
        ready.await()
    }

    private fun setUp() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        EGL14.eglInitialize(display, version, 0, version, 1)
        val attributes = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0)
        config = configs[0]!!
        context = EGL14.eglCreateContext(
            display, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
        )
        encoderSurface = EGL14.eglCreateWindowSurface(display, config, output, intArrayOf(EGL14.EGL_NONE), 0)
        EGL14.eglMakeCurrent(display, encoderSurface, encoderSurface, context)

        program = link(VERTEX, FRAGMENT)
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        texture = ids[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        surfaceTexture = SurfaceTexture(texture).apply {
            setDefaultBufferSize(camera.width, camera.height)
            setOnFrameAvailableListener({ draw() }, handler)
        }
        input = Surface(surfaceTexture)
    }

    /// A new encoder's surface to draw into (another frame rate), in place
    /// of the old one, before the old encoder stops.
    fun setOutput(surface: Surface) {
        val done = java.util.concurrent.CountDownLatch(1)
        handler.post {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, encoderSurface)
            encoderSurface = EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0)
            EGL14.eglMakeCurrent(display, encoderSurface, encoderSurface, context)
            done.countDown()
        }
        done.await(500, java.util.concurrent.TimeUnit.MILLISECONDS)
    }

    /// The camera's output size, before a capture session starts with it.
    /// Waits until the texture has it, so the first frames are sized right.
    fun setCamera(size: android.util.Size) {
        val done = java.util.concurrent.CountDownLatch(1)
        handler.post {
            camera = size
            surfaceTexture.setDefaultBufferSize(size.width, size.height)
            done.countDown()
        }
        done.await(500, java.util.concurrent.TimeUnit.MILLISECONDS)
    }

    /// Shows the stream on the phone too ([surface] null: stops).
    fun setPreview(surface: Surface?) = handler.post {
        previewSurface?.let { EGL14.eglDestroySurface(display, it) }
        previewSurface = surface?.let {
            runCatching { EGL14.eglCreateWindowSurface(display, config, it, intArrayOf(EGL14.EGL_NONE), 0) }
                .getOrNull()?.takeIf { s -> s != EGL14.EGL_NO_SURFACE }
        }
    }

    private fun draw() {
        if (stopped) return
        EGL14.eglMakeCurrent(display, encoderSurface, encoderSurface, context)
        surfaceTexture.updateTexImage()
        surfaceTexture.getTransformMatrix(stMatrix)
        val time = surfaceTexture.timestamp
        render(outW, outH)
        EGLExt.eglPresentationTimeANDROID(display, encoderSurface, time)
        EGL14.eglSwapBuffers(display, encoderSurface)
        previewSurface?.let { preview ->
            if (EGL14.eglMakeCurrent(display, preview, preview, context)) {
                render(outW, outH)
                EGL14.eglSwapBuffers(display, preview)
            }
        }
    }

    /// The picture turned and placed: four corners, each with the camera
    /// texture point it shows.
    private fun render(w: Int, h: Int) {
        GLES20.glViewport(0, 0, w, h)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        val turned = rotation % 180 != 0
        // The picture's shape once turned, against the frame's.
        val picture = if (turned) camera.height.toFloat() / camera.width else camera.width.toFloat() / camera.height
        val frame = w.toFloat() / h
        var sx = 1f
        var sy = 1f
        if (fill) {
            if (picture < frame) sy = frame / picture else sx = picture / frame
        } else {
            if (picture < frame) sx = picture / frame else sy = frame / picture
        }

        quad.clear()
        // Corners in the turned picture (u right, v down) and their place on screen.
        for ((u, v) in listOf(0f to 0f, 1f to 0f, 0f to 1f, 1f to 1f)) {
            val x = (u * 2 - 1) * sx
            val y = (1 - v * 2) * sy
            // The camera picture's point shown there, before turning.
            val (cx, cy) = when (rotation) {
                90 -> v to 1 - u
                180 -> 1 - u to 1 - v
                270 -> 1 - v to u
                else -> u to v
            }
            // Texture space has its origin at the bottom left.
            val s = cx
            val t = 1 - cy
            quad.put(x).put(y)
            quad.put(stMatrix[0] * s + stMatrix[4] * t + stMatrix[12])
            quad.put(stMatrix[1] * s + stMatrix[5] * t + stMatrix[13])
        }
        quad.position(0)

        GLES20.glUseProgram(program)
        val position = GLES20.glGetAttribLocation(program, "aPosition")
        val coord = GLES20.glGetAttribLocation(program, "aCoord")
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(position)
        quad.position(2)
        GLES20.glVertexAttribPointer(coord, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(coord)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    /// A point of the stream (0..1, across and down) as a point of the
    /// camera's own picture, or null in the bars.
    fun toCamera(x: Float, y: Float): Pair<Float, Float>? {
        val turned = rotation % 180 != 0
        val picture = if (turned) camera.height.toFloat() / camera.width else camera.width.toFloat() / camera.height
        val frame = outW.toFloat() / outH
        var sx = 1f
        var sy = 1f
        if (fill) {
            if (picture < frame) sy = frame / picture else sx = picture / frame
        } else {
            if (picture < frame) sx = picture / frame else sy = frame / picture
        }
        val u = (x - 0.5f) / sx + 0.5f
        val v = (y - 0.5f) / sy + 0.5f
        if (u !in 0f..1f || v !in 0f..1f) return null
        return when (rotation) {
            90 -> v to 1 - u
            180 -> 1 - u to 1 - v
            270 -> 1 - v to u
            else -> u to v
        }
    }

    /// Tears down on its thread and waits (briefly) for it, so the encoder's
    /// surface is no longer drawn on when the encoder closes it.
    fun stop() {
        stopped = true
        val done = java.util.concurrent.CountDownLatch(1)
        handler.post {
            runCatching {
                previewSurface?.let { EGL14.eglDestroySurface(display, it) }
                EGL14.eglDestroySurface(display, encoderSurface)
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                EGL14.eglDestroyContext(display, context)
                EGL14.eglTerminate(display)
                input.release()
                surfaceTexture.release()
            }.onFailure { Log.w("linksy", "GL teardown", it) }
            done.countDown()
            thread.quitSafely()
        }
        done.await(500, java.util.concurrent.TimeUnit.MILLISECONDS)
    }

    private fun link(vertex: String, fragment: String): Int {
        fun compile(type: Int, source: String) = GLES20.glCreateShader(type).also {
            GLES20.glShaderSource(it, source)
            GLES20.glCompileShader(it)
        }
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, compile(GLES20.GL_VERTEX_SHADER, vertex))
            GLES20.glAttachShader(it, compile(GLES20.GL_FRAGMENT_SHADER, fragment))
            GLES20.glLinkProgram(it)
        }
    }

    private companion object {
        const val EGL_RECORDABLE_ANDROID = 0x3142
        const val VERTEX = """
            attribute vec4 aPosition;
            attribute vec2 aCoord;
            varying vec2 vCoord;
            void main() { gl_Position = aPosition; vCoord = aCoord; }
        """
        const val FRAGMENT = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vCoord;
            uniform samplerExternalOES uTexture;
            void main() { gl_FragColor = texture2D(uTexture, vCoord); }
        """
    }
}
