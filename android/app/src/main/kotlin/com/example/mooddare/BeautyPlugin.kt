package com.example.mooddare

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper

/** Bundled, on-device detection. Photos are never sent to a face service. */
class BeautyPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
        .setMinFaceSize(0.15f).build())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "detectFace") { result.notImplemented(); return }
        val path = call.argument<String>("path")
        if (path == null) { result.error("invalid_input", "Missing photo.", null); return }
        worker.execute {
            try {
                val file = File(path).canonicalFile
                if (!file.path.startsWith(context.cacheDir.canonicalPath + File.separator)) {
                    throw IllegalArgumentException("Photo must be in the application cache.")
                }
                val image = InputImage.fromFilePath(context, Uri.fromFile(file))
                detector.process(image).addOnSuccessListener { faces ->
                    val face = faces.filter { kotlin.math.abs(it.headEulerAngleY) < 25 &&
                        kotlin.math.abs(it.headEulerAngleZ) < 20 &&
                        it.getLandmark(FaceLandmark.LEFT_EYE) != null &&
                        it.getLandmark(FaceLandmark.RIGHT_EYE) != null &&
                        it.getLandmark(FaceLandmark.MOUTH_BOTTOM) != null }
                        .maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                    if (face == null) { result.success(null); return@addOnSuccessListener }
                    val box = face.boundingBox
                    val w = image.width.toDouble(); val h = image.height.toDouble()
                    val data = mutableMapOf<String, Any>(
                        "x" to box.left / w, "y" to box.top / h,
                        "width" to box.width() / w, "height" to box.height() / h)
                    mapOf("leftEye" to FaceLandmark.LEFT_EYE, "rightEye" to FaceLandmark.RIGHT_EYE,
                        "mouth" to FaceLandmark.MOUTH_BOTTOM, "nose" to FaceLandmark.NOSE_BASE)
                        .forEach { (name, type) -> face.getLandmark(type)?.position?.let {
                            data[name] = listOf(it.x / w, it.y / h)
                        } }
                    result.success(data)
                }.addOnFailureListener { result.error("detection_failed", "Could not detect a face.", null) }
            } catch (e: Exception) {
                main.post { result.error("invalid_photo", "Could not read this photo.", null) }
            }
        }
    }

    fun close() { worker.shutdown(); detector.close() }
}
