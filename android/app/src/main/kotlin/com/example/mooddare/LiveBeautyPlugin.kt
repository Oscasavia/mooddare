package com.example.mooddare

import android.Manifest
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executor
import kotlin.math.abs
import kotlin.math.max

/** A single native session owns camera frames, face tracking, and GPU rendering. */
class LiveBeautyPlugin(
    private val activity: FlutterActivity,
    private val textures: TextureRegistry
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var session: Session? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start", "startFixture" -> {
                if (session != null) { result.error("busy", "Close the current camera first.", null); return }
                val fixture = if (call.method == "startFixture") {
                    // Deterministic GPU integration tests; never available in a release app.
                    if (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                        result.notImplemented(); return
                    }
                    val path = call.argument<String>("path")
                    val file = path?.let { File(it).canonicalFile }
                    if (file == null || !file.path.startsWith(activity.cacheDir.canonicalPath + File.separator)) {
                        result.error("invalid_input", "Fixture must be in the app cache.", null); return
                    }
                    file
                } else null
                if (fixture == null && ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA)
                    != PackageManager.PERMISSION_GRANTED) {
                    result.error("permission", "Allow camera access in phone settings.", null); return
                }
                val current = Session(textures.createSurfaceTexture(), call.argument<Boolean>("front") ?: true)
                session = current
                current.start(fixture, result)
            }
            "status" -> result.success(session?.status() ?: mapOf("ready" to false))
            "setLook" -> {
                val current = session
                if (current == null) result.error("closed", "Camera is closed.", null)
                else current.setLook(call, result)
            }
            "capture" -> {
                val current = session
                if (current == null) result.error("closed", "Camera is closed.", null)
                else current.capture(result)
            }
            "stop" -> {
                val current = session
                session = null
                if (current == null) result.success(null) else current.close { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    fun close() { val old = session; session = null; old?.close {} }

    private inner class Session(val entry: TextureRegistry.SurfaceTextureEntry, val front: Boolean) {
        private val thread = HandlerThread("MoodDareLiveBeauty").apply { start() }
        private val handler = Handler(thread.looper)
        private val executor = Executor { task -> handler.post(task) }
        private val surface = Surface(entry.surfaceTexture())
        private val detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .enableTracking().setMinFaceSize(.15f).build())
        private var provider: ProcessCameraProvider? = null
        private var analysis: ImageAnalysis? = null
        private var renderer: LiveBeautyRenderer? = null
        private var pixels: ByteBuffer? = null
        private var detecting = false
        private var lastDetection = 0L
        private var faceTime = 0L
        private var faceId: Int? = null
        private var trackedFace: FloatArray? = null
        private var fixtureMode = false
        private var count = 0
        private var rateStart = SystemClock.elapsedRealtime()
        @Volatile private var closed = false
        @Volatile private var ready = false
        @Volatile private var width = 0
        @Volatile private var height = 0
        @Volatile private var faceVisible = false
        @Volatile private var fps = 0.0
        @Volatile private var error: String? = null
        @Volatile private var frames = 0L
        @Volatile private var detections = 0L
        private var startResult: MethodChannel.Result? = null

        fun start(fixture: File?, result: MethodChannel.Result) {
            startResult = result
            fixtureMode = fixture != null
            handler.post {
                try {
                    renderer = LiveBeautyRenderer(surface).apply { mirror = front }
                    if (fixture != null) {
                        val bitmap = BitmapFactory.decodeFile(fixture.path)
                            ?: throw IllegalArgumentException("Invalid test image")
                        val rgba = ByteBuffer.allocateDirect(bitmap.width * bitmap.height * 4)
                        bitmap.copyPixelsToBuffer(rgba); rgba.rewind()
                        resize(bitmap.width, bitmap.height)
                        renderer!!.upload(rgba, width, height)
                        renderer!!.draw()
                        ready = true; frames++
                        detect(bitmap)
                    }
                    main.post {
                        if (closed) { finishStartError("closed", "Camera was closed."); return@post }
                        if (fixture != null) finishStart() else bind()
                    }
                } catch (e: Exception) {
                    error = "Could not start the live camera. Return to Photo and try again."
                    main.post { finishStartError("camera", error!!) }
                }
            }
        }

        @Suppress("DEPRECATION")
        private fun bind() {
            val future = ProcessCameraProvider.getInstance(activity)
            future.addListener({
                if (closed) { finishStartError("closed", "Camera was closed."); return@addListener }
                try {
                    provider = future.get()
                    val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                    check(provider!!.hasCamera(selector)) { "This camera is not available" }
                    // Single upright RGBA stream: preview and capture have identical geometry.
                    // CameraX drops old frames; work and memory never queue without bounds.
                    val useCase = ImageAnalysis.Builder()
                        .setTargetResolution(Size(960, 720))
                        .setTargetRotation(Surface.ROTATION_0)
                        .setOutputImageRotationEnabled(true)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis = useCase
                    useCase.setAnalyzer(executor) { image -> render(image) }
                    provider!!.bindToLifecycle(activity, selector, useCase)
                    finishStart()
                } catch (e: Exception) {
                    error = "Could not start this camera. Return to Photo and try again."
                    finishStartError("camera", error!!)
                }
            }, ContextCompat.getMainExecutor(activity))
        }

        private fun finishStart() {
            startResult?.success(mapOf("textureId" to entry.id()))
            startResult = null
        }
        private fun finishStartError(code: String, message: String) {
            startResult?.error(code, message, null)
            startResult = null
        }

        private fun resize(w: Int, h: Int) {
            if (width == w && height == h) return
            width = w; height = h
            entry.surfaceTexture().setDefaultBufferSize(w, h)
            pixels = ByteBuffer.allocateDirect(w * h * 4)
            trackedFace = null; faceVisible = false
        }

        private fun render(image: ImageProxy) {
            try {
                if (closed) return
                resize(image.width, image.height)
                val buffer = pixels!!
                buffer.clear()
                val plane = image.planes[0]
                check(plane.pixelStride == 4) { "Unexpected camera pixel format" }
                val source = plane.buffer.duplicate()
                for (row in 0 until height) {
                    source.limit(source.capacity())
                    source.position(row * plane.rowStride)
                    source.limit(row * plane.rowStride + width * 4)
                    buffer.put(source)
                }
                buffer.flip()
                val now = SystemClock.elapsedRealtime()
                if (!detecting && now - lastDetection >= 90) {
                    lastDetection = now
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    bitmap.copyPixelsFromBuffer(buffer)
                    buffer.rewind()
                    val scale = 480f / max(width, height)
                    val small = Bitmap.createScaledBitmap(bitmap, (width * scale).toInt(), (height * scale).toInt(), true)
                    if (small !== bitmap) bitmap.recycle()
                    detect(small)
                }
                // Never leave a smoothing mask painted over a departed face.
                faceVisible = trackedFace != null && now - faceTime < 350
                renderer!!.face = if (faceVisible) trackedFace else null
                renderer!!.upload(buffer, width, height)
                renderer!!.draw()
                ready = true; frames++; count++
                val elapsed = now - rateStart
                if (elapsed >= 1000) { fps = count * 1000.0 / elapsed; count = 0; rateStart = now }
            } catch (e: Exception) {
                ready = false
                error = "Live preview stopped. Close and reopen the camera."
            } finally { image.close() }
        }

        private fun detect(bitmap: Bitmap) {
            detecting = true
            val submitted = SystemClock.elapsedRealtime()
            detector.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener(executor) { faces ->
                    if (!closed) {
                        val face = faces.filter { abs(it.headEulerAngleX) < 25 && abs(it.headEulerAngleY) < 25 && abs(it.headEulerAngleZ) < 20 &&
                            it.getLandmark(FaceLandmark.LEFT_EYE) != null &&
                            it.getLandmark(FaceLandmark.RIGHT_EYE) != null &&
                            it.getLandmark(FaceLandmark.MOUTH_BOTTOM) != null &&
                            it.getLandmark(FaceLandmark.NOSE_BASE) != null }
                            .maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                        val value = face?.let { coordinates(it, bitmap.width.toFloat(), bitmap.height.toFloat()) }
                        val previous = trackedFace
                        // Modest temporal smoothing; reset when the tracked person changes.
                        trackedFace = if (value != null && previous != null && face.trackingId == faceId) {
                            FloatArray(value.size) { previous[it] * .25f + value[it] * .75f }
                        } else value
                        faceId = face?.trackingId
                        faceTime = submitted
                        faceVisible = value != null && (fixtureMode || SystemClock.elapsedRealtime() - submitted < 350)
                        if (fixtureMode) { renderer?.face = value; renderer?.draw() }
                    }
                }.addOnFailureListener(executor) {
                    trackedFace = null; faceVisible = false
                }.addOnCompleteListener(executor) {
                    bitmap.recycle(); detecting = false; detections++
                    if (closed) finishThread()
                }
        }

        private fun coordinates(face: Face, w: Float, h: Float): FloatArray {
            val box = face.boundingBox
            val result = floatArrayOf(box.left / w, box.top / h, box.width() / w, box.height() / h,
                0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)
            listOf(FaceLandmark.LEFT_EYE, FaceLandmark.RIGHT_EYE, FaceLandmark.MOUTH_BOTTOM, FaceLandmark.NOSE_BASE)
                .forEachIndexed { i, type ->
                    val point = face.getLandmark(type)!!.position
                    result[4 + i * 2] = point.x / w; result[5 + i * 2] = point.y / h
                }
            return result
        }

        fun status(): Map<String, Any?> = mapOf("ready" to ready, "width" to width, "height" to height,
            "faceDetected" to faceVisible, "fps" to fps, "frames" to frames,
            "detections" to detections, "error" to error)

        fun setLook(call: MethodCall, result: MethodChannel.Result) {
            handler.post {
                if (closed) { main.post { result.error("closed", "Camera is closed.", null) }; return@post }
                try {
                    renderer!!.apply {
                        smooth = (call.argument<Number>("smooth")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                        light = (call.argument<Number>("light")?.toFloat() ?: 0f).coerceIn(-1f, 1f)
                        warmth = (call.argument<Number>("warmth")?.toFloat() ?: 0f).coerceIn(-1f, 1f)
                        eyeSize = (call.argument<Number>("eyeSize")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                        faceSlim = (call.argument<Number>("faceSlim")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                        original = call.argument<Boolean>("original") ?: false
                        draw()
                    }
                    main.post { result.success(null) }
                } catch (e: Exception) { main.post { result.error("render", "Could not apply this look.", null) } }
            }
        }

        fun capture(result: MethodChannel.Result) {
            handler.post {
                try {
                    check(!closed && ready) { "Camera is not ready" }
                    val file = File(activity.cacheDir, "mooddare-live-${UUID.randomUUID()}.jpg")
                    renderer!!.capture(file)
                    main.post { result.success(file.path) }
                } catch (e: Exception) { main.post { result.error("capture", "Could not take this photo. Try again.", null) } }
            }
        }

        fun close(done: () -> Unit) {
            if (closed) { done(); return }
            closed = true; ready = false
            finishStartError("closed", "Camera was closed.")
            analysis?.let { it.clearAnalyzer(); provider?.unbind(it) }
            handler.post {
                renderer?.close(); renderer = null
                surface.release()
                main.post { entry.release(); done() }
                if (!detecting) finishThread()
            }
        }
        private fun finishThread() { detector.close(); thread.quitSafely() }
    }
}
