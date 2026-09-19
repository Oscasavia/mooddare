package com.example.mooddare

import android.graphics.Bitmap
import android.graphics.Matrix
import android.opengl.EGL14
import android.opengl.GLES20
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Owned exclusively by the camera's render thread. No pixels cross into Dart. */
internal class LiveBeautyRenderer(surface: Surface) {
    private val display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private val context: android.opengl.EGLContext
    private val window: android.opengl.EGLSurface
    private val program: Int
    private val texture: Int
    private val vertices = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply { put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0) }
    var width = 0; private set
    var height = 0; private set
    var mirror = true
    var smooth = .35f
    var light = 0f
    var warmth = 0f
    var eyeSize = 0f
    var faceSlim = 0f
    var original = false
    var face: FloatArray? = null

    init {
        check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 0))
        val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
        val count = IntArray(1)
        check(EGL14.eglChooseConfig(display, intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_NONE
        ), 0, configs, 0, 1, count, 0) && count[0] > 0)
        context = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        window = EGL14.eglCreateWindowSurface(display, configs[0], surface,
            intArrayOf(EGL14.EGL_NONE), 0)
        check(EGL14.eglMakeCurrent(display, window, window, context))
        val vertex = shader(GLES20.GL_VERTEX_SHADER, VERTEX)
        val fragment = shader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT)
        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)
        val linked = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linked, 0)
        check(linked[0] != 0) { GLES20.glGetProgramInfoLog(program) }
        GLES20.glDeleteShader(vertex); GLES20.glDeleteShader(fragment)
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        texture = textures[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    fun upload(bytes: ByteBuffer, w: Int, h: Int) {
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        bytes.position(0)
        if (w != width || h != height) {
            width = w; height = h
            GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, w, h, 0,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bytes)
        } else {
            GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, w, h,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bytes)
        }
    }

    fun draw(present: Boolean = true) {
        if (width == 0) return
        GLES20.glViewport(0, 0, width, height)
        GLES20.glUseProgram(program)
        val position = GLES20.glGetAttribLocation(program, "position")
        GLES20.glEnableVertexAttribArray(position)
        vertices.position(0)
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 0, vertices)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(uniform("image"), 0)
        GLES20.glUniform1f(uniform("mirror"), if (mirror) 1f else 0f)
        GLES20.glUniform2f(uniform("stepSize"), 2f / width, 2f / height)
        val f = face
        GLES20.glUniform4f(uniform("settings"), if (original) 0f else smooth,
            if (original) 0f else light, if (original) 0f else warmth, if (f == null) 0f else 1f)
        GLES20.glUniform2f(uniform("shape"), if (original) 0f else eyeSize, if (original) 0f else faceSlim)
        GLES20.glUniform4fv(uniform("face"), 1, f ?: FloatArray(12), 0)
        GLES20.glUniform4fv(uniform("eyes"), 1, f ?: FloatArray(12), 4)
        GLES20.glUniform4fv(uniform("features"), 1, f ?: FloatArray(12), 8)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        check(GLES20.glGetError() == GLES20.GL_NO_ERROR) { "GPU rendering failed" }
        if (present) check(EGL14.eglSwapBuffers(display, window)) { "Preview surface lost" }
    }

    /** Read the same shader output before swap; EGL back buffers are not preserved. */
    fun capture(file: File) {
        check(width > 0) { "Camera is not ready" }
        draw(present = false)
        val pixels = ByteBuffer.allocateDirect(width * height * 4)
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
        check(GLES20.glGetError() == GLES20.GL_NO_ERROR)
        val bottomUp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        pixels.position(0)
        bottomUp.copyPixelsFromBuffer(pixels)
        val upright = Bitmap.createBitmap(bottomUp, 0, 0, width, height,
            Matrix().apply { preScale(1f, -1f) }, false)
        try {
            file.outputStream().use { check(upright.compress(Bitmap.CompressFormat.JPEG, 95, it)) }
        } finally {
            if (upright !== bottomUp) upright.recycle()
            bottomUp.recycle()
        }
        check(EGL14.eglSwapBuffers(display, window))
    }

    fun close() {
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
        GLES20.glDeleteProgram(program)
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(display, window)
        EGL14.eglDestroyContext(display, context)
        EGL14.eglReleaseThread()
        EGL14.eglTerminate(display)
    }

    private fun uniform(name: String) = GLES20.glGetUniformLocation(program, name)
    private fun shader(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source); GLES20.glCompileShader(shader)
        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        check(compiled[0] != 0) { GLES20.glGetShaderInfoLog(shader) }
        return shader
    }

    companion object {
        private const val VERTEX = """
            attribute vec2 position;
            varying vec2 uv;
            void main() {
                gl_Position = vec4(position, 0.0, 1.0);
                uv = vec2((position.x + 1.0) * 0.5, (1.0 - position.y) * 0.5);
            }
        """
        private const val FRAGMENT = """
            precision mediump float;
            varying vec2 uv;
            uniform sampler2D image;
            uniform vec2 stepSize;
            uniform float mirror;
            uniform vec4 settings;
            uniform vec4 face;
            uniform vec4 eyes;
            uniform vec4 features;
            uniform vec2 shape;
            float ellipse(vec2 p, vec2 center, vec2 radius) {
                vec2 d = (p - center) / max(radius, vec2(0.0001));
                return dot(d, d);
            }
            float protect(vec2 p, vec2 center, vec2 radius) {
                return clamp((ellipse(p, center, radius) - 1.0) / 0.65, 0.0, 1.0);
            }
            vec2 enlargeEye(vec2 p, vec2 center) {
                float distance = ellipse(p, center, face.zw * vec2(0.23, 0.15));
                float falloff = pow(1.0 - clamp(distance, 0.0, 1.0), 2.0);
                return center + (p - center) * (1.0 - shape.x * 0.28 * falloff);
            }
            void main() {
                vec2 p = vec2(mix(uv.x, 1.0 - uv.x, mirror), uv.y);
                if (settings.w > 0.5) {
                    // Inverse texture warps remain local and feather to zero at the boundary.
                    float d = ellipse(p, face.xy + face.zw * vec2(0.5, 0.63), face.zw * vec2(0.65, 0.6));
                    float y = (p.y - face.y) / max(face.w, 0.0001);
                    float jaw = smoothstep(0.35, 0.65, y) * (1.0 - smoothstep(0.85, 1.18, y));
                    p.x += (p.x - face.x - face.z * 0.5) * shape.y * 0.24 * jaw *
                        pow(1.0 - clamp(d, 0.0, 1.0), 2.0);
                    p = enlargeEye(p, eyes.xy);
                    p = enlargeEye(p, eyes.zw);
                }
                vec3 color = texture2D(image, p).rgb;
                if (settings.x > 0.0 && settings.w > 0.5) {
                    float mask = clamp((1.0 - ellipse(p, face.xy + face.zw * vec2(0.5, 0.53),
                        face.zw * vec2(0.44, 0.43))) / 0.25, 0.0, 1.0);
                    mask *= protect(p, eyes.xy, face.zw * vec2(0.19, 0.10));
                    mask *= protect(p, eyes.zw, face.zw * vec2(0.19, 0.10));
                    mask *= protect(p, features.xy, face.zw * vec2(0.29, 0.13));
                    mask *= protect(p, features.zw, face.zw * vec2(0.19, 0.10));
                    if (mask > 0.0) {
                        vec3 sum = vec3(0.0);
                        float total = 0.0;
                        for (int y = -2; y <= 2; y++) {
                            for (int x = -2; x <= 2; x++) {
                                vec2 offset = vec2(float(x), float(y));
                                vec3 sampleColor = texture2D(image, p + offset * stepSize).rgb;
                                vec3 diff = sampleColor - color;
                                float weight = exp(-dot(offset, offset) / 5.0 - dot(diff, diff) * 36.125);
                                sum += sampleColor * weight;
                                total += weight;
                            }
                        }
                        color = mix(color, sum / total, settings.x * mask);
                    }
                }
                color = color * exp2(settings.y * 0.6) + vec3(settings.z, 0.0, -settings.z) * (14.0 / 255.0);
                gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
            }
        """
    }
}
