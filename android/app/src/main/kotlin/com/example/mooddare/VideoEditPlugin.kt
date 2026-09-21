package com.example.mooddare

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Exports a new MP4. Audio removal and trimming are baked into the file. */
class VideoEditPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private var output: File? = null
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "export") { result.notImplemented(); return }
        if (pending != null) { result.error("busy", "A video is already exporting.", null); return }
        try {
            val input = File(requireNotNull(call.argument<String>("input"))).canonicalFile
            val target = File(requireNotNull(call.argument<String>("output"))).canonicalFile
            require(input.isFile && input != target && !target.exists())
            require(target.path.startsWith(context.cacheDir.canonicalPath + File.separator))
            val start = requireNotNull(call.argument<Number>("startMs")).toLong()
            val end = requireNotNull(call.argument<Number>("endMs")).toLong()
            val metadata = MediaMetadataRetriever()
            val duration = try {
                metadata.setDataSource(input.path)
                requireNotNull(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)).toLong()
            } finally { metadata.release() }
            require(start >= 0 && end > start && end <= duration + 100)
            val clip = MediaItem.ClippingConfiguration.Builder().setStartPositionMs(start)
                .setEndPositionMs(minOf(end, duration)).build()
            val item = EditedMediaItem.Builder(MediaItem.Builder().setUri(Uri.fromFile(input))
                .setClippingConfiguration(clip).build())
                .setRemoveAudio(call.argument<Boolean>("muted") == true).build()
            pending = result
            output = target
            // Do not enable edit-list trimming: excluded footage must not remain
            // hidden inside a file that the user can share or download.
            transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        val reply = pending
                        pending = null; transformer = null; output = null
                        if (target.isFile && target.length() > 0) reply?.success(target.path)
                        else { target.delete(); reply?.error("export", "Empty video export.", null) }
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) {
                        fail("Could not export this video.")
                    }
                }).build()
            transformer!!.start(item, target.path)
        } catch (e: Exception) {
            if (pending != null) fail("Could not export this video.")
            else result.error("invalid-video", "Invalid video or trim range.", null)
        }
    }
    private fun fail(message: String) {
        transformer?.cancel(); transformer = null
        output?.delete(); output = null
        val reply = pending; pending = null
        reply?.error("export", message, null)
    }
    fun close() { if (pending != null) fail("Video export interrupted.") }
}
