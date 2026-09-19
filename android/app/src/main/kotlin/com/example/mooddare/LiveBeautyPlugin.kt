package com.example.mooddare

import android.Manifest
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Size
import android.util.Rational
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.Camera
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
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
import kotlin.math.max
import kotlin.math.min

/** A single native session owns camera frames, face tracking, and GPU rendering. */
class LiveBeautyPlugin(
    private val activity: FlutterActivity,
    private val textures: TextureRegistry
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var session: Session? = null
    @Volatile private var pendingVideo: String? = null
    private var permissionResult: MethodChannel.Result? = null
    private var permissionRequest = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspectVideo" -> {
                if (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) { result.notImplemented(); return }
                val file = call.argument<String>("path")?.let { File(it).canonicalFile }
                if (file == null || !file.path.startsWith(activity.cacheDir.canonicalPath + File.separator)) {
                    result.error("invalid_input", "Video must be in the app cache.", null); return
                }
                Thread {
                    val extractor = MediaExtractor()
                    try {
                        extractor.setDataSource(file.path)
                        val tracks = (0 until extractor.trackCount).map { index ->
                            val format = extractor.getTrackFormat(index)
                            mapOf("mime" to format.getString(MediaFormat.KEY_MIME),
                                "durationUs" to if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L)
                        }
                        main.post { result.success(tracks) }
                    } catch (_: Exception) { main.post { result.error("video", "Could not inspect video.", null) } }
                    finally { extractor.release() }
                }.start()
            }
            "requestMicrophone", "requestCamera" -> {
                val permission = if (call.method == "requestCamera") Manifest.permission.CAMERA else Manifest.permission.RECORD_AUDIO
                if (ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (call.argument<Boolean>("prompt") == false) {
                    result.success(false)
                } else if (permissionResult != null) {
                    result.error("busy", "A permission request is already open.", null)
                } else {
                    permissionResult = result
                    permissionRequest = if (call.method == "requestCamera") 7425 else 7426
                    ActivityCompat.requestPermissions(activity, arrayOf(permission), permissionRequest)
                }
            }
            "takePendingVideo" -> { val path = pendingVideo; pendingVideo = null; result.success(path) }
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
            "status" -> result.success((session?.status() ?: mapOf("ready" to false)) +
                mapOf("screenBrightness" to activity.window.attributes.screenBrightness))
            "setLook" -> {
                val current = session
                if (current == null) result.error("closed", "Camera is closed.", null)
                else current.setLook(call, result)
            }
            "capture", "captureStillFixture" -> {
                val fixture = call.method == "captureStillFixture"
                if (fixture && activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                    result.notImplemented(); return
                }
                val current = session
                if (current == null) result.error("closed", "Camera is closed.", null)
                else current.capture(result, call.argument<Boolean>("flash") ?: false, fixture)
            }
            "setCaptureLight" -> {
                val current = session
                if (current == null) {
                    if (call.argument<Boolean>("enabled") == true) result.error("closed", "Camera is closed.", null)
                    else result.success(null)
                } else current.setCaptureLight(call.argument<Boolean>("enabled") ?: false, result)
            }
            "startRecording" -> {
                val current = session
                if (current == null) result.error("closed", "Camera is closed.", null)
                else if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    result.error("microphone", "Allow microphone access to record video with audio.", null)
                } else current.startRecording(result)
            }
            "stopRecording" -> {
                val current = session
                if (current == null) {
                    val path = pendingVideo; pendingVideo = null
                    if (path != null) result.success(path) else result.error("closed", "No video was recorded.", null)
                } else current.stopRecording(result)
            }
            "stop" -> {
                val current = session
                session = null
                if (current == null) result.success(null) else current.close { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != permissionRequest) return
        permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permissionResult = null
        permissionRequest = 0
    }

    // Native lifecycle protection stops the microphone even if Dart is paused.
    fun onPause() { session?.clearCaptureLight(); session?.interruptRecording() }

    fun close() {
        permissionResult?.success(false); permissionResult = null
        val old = session; session = null; old?.close {}
    }

    private inner class Session(val entry: TextureRegistry.SurfaceTextureEntry, val front: Boolean) {
        private val thread = HandlerThread("MoodDareLiveBeauty").apply { start() }
        private val handler = Handler(thread.looper)
        private val executor = Executor { task -> handler.post(task) }
        private val surface = Surface(entry.surfaceTexture())
        private val detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .enableTracking().setMinFaceSize(.15f).build())
        private val photoDetector = FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setMinFaceSize(.15f).build())
        private var provider: ProcessCameraProvider? = null
        private var camera: Camera? = null
        private var savedBrightness: Float? = null
        private var lightResult: MethodChannel.Result? = null
        @Volatile private var captureLight = false
        @Volatile private var lightFrame = 0L
        private val lightTimeout = Runnable { clearCaptureLight() }
        private var analysis: ImageAnalysis? = null
        private var stillCapture: ImageCapture? = null
        private var photoResult: MethodChannel.Result? = null
        private var photoDetecting = false
        private var threadFinished = false
        private val photoTimeout = Runnable { finishPhoto(null, "Photo capture timed out. Please try again.") }
        private var renderer: LiveBeautyRenderer? = null
        private var pixels: ByteBuffer? = null
        private var detecting = false
        private var lastDetection = 0L
        private val faceTracker = FaceStabilizer()
        private var fixtureMode = false
        private var fixtureFile: File? = null
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
        private var recorder: LiveBeautyRecorder? = null
        @Volatile private var recording = false
        @Volatile private var recordingStarted = 0L
        @Volatile private var recordingError: String? = null
        private val recordingLimit = Runnable { finishRecording() }
        private val fixtureFrames = object : Runnable {
            override fun run() {
                if (closed || !recording) return
                try { renderer?.draw(recordFrame = true); frames++ }
                catch (_: Exception) { finishRecording() }
                if (recording) handler.postDelayed(this, 33)
            }
        }

        fun start(fixture: File?, result: MethodChannel.Result) {
            startResult = result
            fixtureMode = fixture != null
            fixtureFile = fixture
            handler.post {
                try {
                    renderer = LiveBeautyRenderer(surface).apply { mirror = front }
                    if (fixture != null) {
                        val originalBitmap = BitmapFactory.decodeFile(fixture.path)
                            ?: throw IllegalArgumentException("Invalid test image")
                        val scale = min(1f, 1280f / max(originalBitmap.width, originalBitmap.height))
                        val bitmap = if (scale < 1f) Bitmap.createScaledBitmap(originalBitmap,
                            (originalBitmap.width * scale).toInt(), (originalBitmap.height * scale).toInt(), true) else originalBitmap
                        if (bitmap !== originalBitmap) originalBitmap.recycle()
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
                    // The viewport aligns preview/still crop rectangles on the sensor.
                    // Keep preview resolution low; only shutter captures use a larger image.
                    val useCase = ImageAnalysis.Builder()
                        .setTargetResolution(Size(960, 720))
                        .setTargetRotation(Surface.ROTATION_0)
                        .setOutputImageRotationEnabled(true)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    analysis = useCase
                    useCase.setAnalyzer(executor) { image -> render(image) }
                    val still = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                        .setTargetRotation(Surface.ROTATION_0)
                        .setJpegQuality(95)
                        .setResolutionSelector(ResolutionSelector.Builder()
                            .setResolutionStrategy(ResolutionStrategy(Size(2048, 1536),
                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
                            .setResolutionFilter { sizes, _ ->
                                sizes.filter { max(it.width, it.height) <= 3072 }
                                    .ifEmpty { listOf(sizes.minBy { it.width.toLong() * it.height }) }
                            }.build())
                        .build()
                    val group = UseCaseGroup.Builder().addUseCase(useCase).addUseCase(still)
                        .setViewPort(ViewPort.Builder(Rational(3, 4), Surface.ROTATION_0)
                            .setScaleType(ViewPort.FILL_CENTER).build()).build()
                    try {
                        camera = provider!!.bindToLifecycle(activity, selector, group)
                        stillCapture = still
                    } catch (_: IllegalArgumentException) {
                        // Some older cameras cannot support both streams. Preserve capture.
                        provider!!.unbind(useCase, still)
                        camera = provider!!.bindToLifecycle(activity, selector, useCase)
                        stillCapture = null
                    }
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
            faceTracker.reset(); faceVisible = false
        }

        private fun render(image: ImageProxy) {
            try {
                if (closed) return
                val crop = image.cropRect
                resize(crop.width(), crop.height())
                val buffer = pixels!!
                buffer.clear()
                val plane = image.planes[0]
                check(plane.pixelStride == 4) { "Unexpected camera pixel format" }
                val source = plane.buffer.duplicate()
                for (row in 0 until height) {
                    source.limit(source.capacity())
                    val start = (row + crop.top) * plane.rowStride + crop.left * 4
                    source.position(start)
                    source.limit(start + width * 4)
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
                updateTrackedFace(now)
                renderer!!.upload(buffer, width, height)
                renderer!!.draw(recordFrame = recording)
                ready = true; frames++; count++
                val elapsed = now - rateStart
                if (elapsed >= 1000) { fps = count * 1000.0 / elapsed; count = 0; rateStart = now }
            } catch (e: Exception) {
                ready = false
                error = "Live preview stopped. Close and reopen the camera."
                finishRecording()
            } finally { image.close() }
        }

        private fun detect(bitmap: Bitmap) {
            detecting = true
            val submitted = SystemClock.elapsedRealtime()
            detector.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener(executor) { faces ->
                    if (!closed) {
                        val observations = faces.map { face ->
                            val usable = face.getLandmark(FaceLandmark.LEFT_EYE) != null &&
                                face.getLandmark(FaceLandmark.RIGHT_EYE) != null &&
                                face.getLandmark(FaceLandmark.MOUTH_BOTTOM) != null &&
                                face.getLandmark(FaceLandmark.NOSE_BASE) != null
                            FaceObservation(face.trackingId,
                                face.boundingBox.width().toFloat() * face.boundingBox.height(),
                                if (usable) coordinates(face, bitmap.width.toFloat(), bitmap.height.toFloat()) else null,
                                face.headEulerAngleX, face.headEulerAngleY, face.headEulerAngleZ)
                        }
                        val now = SystemClock.elapsedRealtime()
                        if (fixtureMode) {
                            // A still fixture has no timeline; evaluate its settled pose.
                            val face = observations.maxByOrNull { it.area }
                            val value = face?.points?.takeIf { FaceStabilizer.valid(it) }
                            val strength = face?.let { FaceStabilizer.poseStrength(it.pitch, it.yaw, it.roll) } ?: 0f
                            faceVisible = value != null && strength > 0f
                            renderer?.face = if (faceVisible) value else null
                            renderer?.faceStrength = strength
                            renderer?.draw()
                        } else {
                            faceTracker.update(observations, submitted, now)
                            updateTrackedFace(now)
                        }
                    }
                }.addOnFailureListener(executor) {
                    faceTracker.reset(); faceVisible = false
                    renderer?.face = null
                }.addOnCompleteListener(executor) {
                    bitmap.recycle(); detecting = false; detections++
                    if (closed) maybeFinishThread()
                }
        }

        private fun updateTrackedFace(now: Long) {
            val tracked = faceTracker.sample(now)
            faceVisible = tracked != null && tracked.strength > .01f
            renderer?.face = tracked?.points
            renderer?.faceStrength = tracked?.strength ?: 0f
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
            "front" to front,
            "highQualityPhotos" to (stillCapture != null),
            "hasFlash" to (camera?.cameraInfo?.hasFlashUnit() ?: false), "captureLight" to captureLight,
            "faceDetected" to faceVisible, "fps" to fps, "frames" to frames,
            "detections" to detections, "error" to error,
            "recording" to recording, "recordingMillis" to if (recording) SystemClock.elapsedRealtime() - recordingStarted else 0L,
            "videoReady" to (pendingVideo != null), "recordingError" to recordingError)

        // Main-thread ownership keeps brightness and torch cleanup independent of Dart.
        fun setCaptureLight(enabled: Boolean, result: MethodChannel.Result) {
            if (!enabled) { clearCaptureLight(); result.success(null); return }
            if (closed || !ready || recording || captureLight) {
                result.error("flash", "Photo flash is not ready. Try again.", null); return
            }
            if (!front && camera?.cameraInfo?.hasFlashUnit() != true) {
                result.error("flash", "This camera has no flash.", null); return
            }
            captureLight = true
            lightFrame = frames
            lightResult = result
            // Fail-safe for interruptions, stalled captures, or a disconnected Dart client.
            main.postDelayed(lightTimeout, 3000)
            try {
                if (front) {
                    savedBrightness = activity.window.attributes.screenBrightness
                    activity.window.attributes = activity.window.attributes.apply { screenBrightness = 1f }
                    lightResult = null
                    result.success(null)
                } else {
                    val future = camera!!.cameraControl.enableTorch(true)
                    future.addListener({
                        // Clearing the light already completes a pending result.
                        if (lightResult !== result) return@addListener
                        try {
                            future.get()
                            lightFrame = frames
                            lightResult = null
                            result.success(null)
                        } catch (_: Exception) { clearCaptureLight() }
                    }, ContextCompat.getMainExecutor(activity))
                }
            } catch (_: Exception) { clearCaptureLight() }
        }

        fun clearCaptureLight() {
            main.removeCallbacks(lightTimeout)
            val wasOn = captureLight
            captureLight = false
            savedBrightness?.let { brightness ->
                activity.window.attributes = activity.window.attributes.apply { screenBrightness = brightness }
            }
            savedBrightness = null
            if (wasOn && !front) {
                try { camera?.cameraControl?.enableTorch(false) } catch (_: Exception) { }
            }
            val pending = lightResult; lightResult = null
            pending?.error("flash", "Photo flash was interrupted. Please try again.", null)
        }

        fun startRecording(result: MethodChannel.Result) {
            handler.post {
                var candidate: LiveBeautyRecorder? = null
                try {
                    check(!closed && ready && recorder == null && pendingVideo == null && !captureLight && photoResult == null && !photoDetecting)
                    val crop = renderer!!.captureSize()
                    val scale = min(1.0, min(1280.0 / max(crop.first, crop.second), 720.0 / min(crop.first, crop.second)))
                    val w = (crop.first * scale / 2).toInt() * 2
                    val h = (crop.second * scale / 2).toInt() * 2
                    candidate = LiveBeautyRecorder(activity, File(activity.cacheDir, "mooddare-live-${UUID.randomUUID()}.mp4"), w, h) {
                        handler.post { if (recorder === candidate) finishRecording() }
                    }
                    renderer!!.attachRecorder(candidate.surface, w, h)
                    candidate.start()
                    recorder = candidate
                    recordingStarted = SystemClock.elapsedRealtime()
                    recordingError = null; recording = true
                    handler.postDelayed(recordingLimit, 30_000)
                    if (fixtureMode) handler.post(fixtureFrames)
                    main.post { result.success(null) }
                } catch (e: Exception) {
                    if (candidate != null) { renderer?.detachRecorder(); candidate.abort() }
                    main.post { result.error("recording", "Could not start video. Check microphone access and try again.", null) }
                }
            }
        }

        private fun finishRecording() {
            val current = recorder ?: return
            recorder = null; recording = false
            handler.removeCallbacks(recordingLimit); handler.removeCallbacks(fixtureFrames)
            renderer?.detachRecorder()
            try { pendingVideo = current.finish().path }
            catch (_: Exception) { recordingError = "The clip was too short or interrupted. Please record again." }
        }

        fun stopRecording(result: MethodChannel.Result) {
            handler.post {
                finishRecording()
                val path = pendingVideo; pendingVideo = null
                main.post {
                    if (path != null) result.success(path)
                    else result.error("recording", recordingError ?: "No video was recorded.", null)
                }
            }
        }

        fun interruptRecording() { handler.post { finishRecording() } }

        fun setLook(call: MethodCall, result: MethodChannel.Result) {
            handler.post {
                if (closed) { main.post { result.error("closed", "Camera is closed.", null) }; return@post }
                if (photoResult != null) { main.post { result.error("busy", "Wait for the photo to finish.", null) }; return@post }
                try {
                    renderer!!.apply {
                        smooth = (call.argument<Number>("smooth")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                        light = (call.argument<Number>("light")?.toFloat() ?: 0f).coerceIn(-1f, 1f)
                        warmth = (call.argument<Number>("warmth")?.toFloat() ?: 0f).coerceIn(-1f, 1f)
                        eyeSize = (call.argument<Number>("eyeSize")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                        faceSlim = (call.argument<Number>("faceSlim")?.toFloat() ?: 0f).coerceIn(0f, 1f)
                        original = call.argument<Boolean>("original") ?: false
                        if (call.hasArgument("aspectRatio") && !recording) {
                            outputAspect = call.argument<Number>("aspectRatio")?.toFloat()?.coerceIn(.3f, 3f)
                        }
                        draw()
                    }
                    main.post { result.success(null) }
                } catch (e: Exception) { main.post { result.error("render", "Could not apply this look.", null) } }
            }
        }

        fun capture(result: MethodChannel.Result, flash: Boolean = false, highQualityFixture: Boolean = false) {
            handler.post {
                try {
                    check(!closed && ready) { "Camera is not ready" }
                    check(!recording && photoResult == null && !photoDetecting) { "Capture is busy" }
                    check(!flash || (captureLight && frames > lightFrame + 2)) { "Wait for an illuminated frame" }
                    val still = stillCapture
                    if (highQualityFixture) {
                        check(fixtureMode)
                        val decoded = BitmapFactory.decodeFile(fixtureFile!!.path)
                            ?: throw IllegalArgumentException("Invalid test image")
                        val scale = min(1f, 2048f / max(decoded.width, decoded.height))
                        val bitmap = if (scale < 1f) Bitmap.createScaledBitmap(decoded,
                            (decoded.width * scale).toInt(), (decoded.height * scale).toInt(), true) else decoded
                        if (bitmap !== decoded) decoded.recycle()
                        val file = File(activity.cacheDir, "mooddare-still-fixture-${UUID.randomUUID()}.jpg")
                        try { renderer!!.captureStill(bitmap, file, renderer!!.face, renderer!!.faceStrength) }
                        finally { bitmap.recycle() }
                        main.post { result.success(file.path) }
                    } else if (fixtureMode || still == null) {
                        val file = File(activity.cacheDir, "mooddare-live-${UUID.randomUUID()}.jpg")
                        renderer!!.capture(file)
                        main.post { result.success(file.path) }
                    } else {
                        photoResult = result
                        val anchor = renderer!!.face?.copyOf()
                        handler.postDelayed(photoTimeout, 20_000)
                        main.post {
                            if (!closed) {
                                try {
                                    still.takePicture(ContextCompat.getMainExecutor(activity), object : ImageCapture.OnImageCapturedCallback() {
                                        override fun onCaptureSuccess(image: ImageProxy) {
                                            if (closed || !handler.post { processStill(image, anchor, result) }) image.close()
                                        }
                                        override fun onError(exception: ImageCaptureException) {
                                            handler.post { if (photoResult === result) finishPhoto(null, "Could not take this photo. Please try again.") }
                                        }
                                    })
                                } catch (_: Exception) {
                                    handler.post { if (photoResult === result) finishPhoto(null, "Could not take this photo. Please try again.") }
                                }
                            }
                        }
                    }
                } catch (e: Exception) { main.post { result.error("capture", "Could not take this photo. Try again.", null) } }
            }
        }

        private fun processStill(image: ImageProxy, anchor: FloatArray?, request: MethodChannel.Result) {
            var bitmap: Bitmap? = null
            try {
                if (closed || photoResult !== request) return
                val decoded = image.toBitmap()
                try {
                    val crop = image.cropRect
                    val scale = min(1f, 2048f / max(crop.width(), crop.height()))
                    bitmap = Bitmap.createBitmap(decoded, crop.left, crop.top, crop.width(), crop.height(),
                        Matrix().apply { postRotate(image.imageInfo.rotationDegrees.toFloat()); postScale(scale, scale) }, true)
                } finally { if (bitmap !== decoded) decoded.recycle() }
            } catch (_: Exception) {
                finishPhoto(null, "Could not process this photo. Please try again.")
            } finally { image.close() }
            val photo = bitmap ?: return
            if (closed || photoResult !== request) { photo.recycle(); return }
            val output = renderer!!
            if (output.original || (output.smooth == 0f && output.eyeSize == 0f && output.faceSlim == 0f)) {
                try { renderStill(photo, null, 0f) } finally { photo.recycle() }
                return
            }
            photoDetecting = true
            try {
                photoDetector.process(InputImage.fromBitmap(photo, 0))
                    .addOnSuccessListener(executor) { faces ->
                        if (!closed && photoResult === request) {
                            val candidates = faces.mapNotNull { face ->
                                val types = listOf(FaceLandmark.LEFT_EYE, FaceLandmark.RIGHT_EYE, FaceLandmark.MOUTH_BOTTOM, FaceLandmark.NOSE_BASE)
                                if (types.any { face.getLandmark(it) == null }) null else {
                                    val points = coordinates(face, photo.width.toFloat(), photo.height.toFloat())
                                    if (!FaceStabilizer.valid(points)) null else Pair(face, points)
                                }
                            }
                            // A still may arrive after movement. Re-detect on the still itself;
                            // never reuse preview landmarks on a different exposure.
                            val picked = if (anchor == null) candidates.maxByOrNull { it.second[2] * it.second[3] }
                                else candidates.minByOrNull { faceDistance(it.second, anchor) }
                                    ?.takeIf { faceDistance(it.second, anchor) < 1f }
                            val quality = picked?.first?.let { FaceStabilizer.poseStrength(it.headEulerAngleX, it.headEulerAngleY, it.headEulerAngleZ) } ?: 0f
                            renderStill(photo, picked?.second, quality)
                        }
                    }.addOnFailureListener(executor) {
                        if (photoResult === request) finishPhoto(null, "Could not apply this lens. Please try again.")
                    }.addOnCompleteListener(executor) {
                        photo.recycle(); photoDetecting = false
                        if (closed) maybeFinishThread()
                    }
            } catch (_: Exception) {
                photo.recycle(); photoDetecting = false
                finishPhoto(null, "Could not apply this lens. Please try again.")
            }
        }

        private fun faceDistance(face: FloatArray, anchor: FloatArray): Float {
            val dx = (face[0] + face[2] * .5f - anchor[0] - anchor[2] * .5f) / anchor[2]
            val dy = (face[1] + face[3] * .5f - anchor[1] - anchor[3] * .5f) / anchor[3]
            return dx * dx + dy * dy
        }

        private fun renderStill(photo: Bitmap, points: FloatArray?, strength: Float) {
            val file = File(activity.cacheDir, "mooddare-live-${UUID.randomUUID()}.jpg")
            try {
                renderer!!.captureStill(photo, file, points, strength)
                finishPhoto(file.path)
            } catch (_: Exception) {
                file.delete()
                finishPhoto(null, "Could not finish this photo. Please try again.")
            }
        }

        private fun finishPhoto(path: String?, message: String = "Photo capture was interrupted.") {
            handler.removeCallbacks(photoTimeout)
            val pending = photoResult ?: return
            photoResult = null
            main.post {
                if (path != null) pending.success(path)
                else pending.error("capture", message, null)
            }
        }

        fun close(done: () -> Unit) {
            if (closed) { done(); return }
            closed = true; ready = false
            clearCaptureLight()
            finishStartError("closed", "Camera was closed.")
            analysis?.let { it.clearAnalyzer(); provider?.unbind(it) }
            stillCapture?.let { provider?.unbind(it) }; stillCapture = null
            handler.post {
                finishPhoto(null)
                finishRecording()
                renderer?.close(); renderer = null
                surface.release()
                main.post { entry.release(); done() }
                maybeFinishThread()
            }
        }
        private fun maybeFinishThread() {
            if (!closed || detecting || photoDetecting || threadFinished) return
            threadFinished = true
            detector.close(); photoDetector.close(); thread.quitSafely()
        }
    }
}
