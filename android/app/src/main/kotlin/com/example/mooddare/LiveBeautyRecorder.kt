package com.example.mooddare

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import java.io.File

/** MediaRecorder handles H.264/AAC muxing; video pixels come only from our GPU. */
internal class LiveBeautyRecorder(
    context: Context,
    val file: File,
    val width: Int,
    val height: Int,
    onLimit: () -> Unit
) {
    @Suppress("DEPRECATION")
    private val recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
    val surface: Surface
    private var started = false

    init {
        try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setVideoSize(width, height)
            recorder.setVideoFrameRate(30)
            recorder.setVideoEncodingBitRate(4_000_000)
            recorder.setAudioChannels(1)
            recorder.setAudioEncodingBitRate(96_000)
            recorder.setAudioSamplingRate(44_100)
            recorder.setMaxDuration(30_000)
            recorder.setMaxFileSize(28L * 1024 * 1024)
            recorder.setOutputFile(file.absolutePath)
            recorder.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED ||
                    what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) onLimit()
            }
            recorder.setOnErrorListener { _, _, _ -> onLimit() }
            recorder.prepare()
            surface = recorder.surface
        } catch (e: Exception) {
            recorder.release(); file.delete(); throw e
        }
    }

    fun start() { recorder.start(); started = true }

    fun finish(): File {
        try {
            check(started)
            recorder.stop()
            check(file.length() > 0)
            return file
        } catch (e: Exception) {
            file.delete(); throw e
        } finally { recorder.release(); surface.release() }
    }

    fun abort() {
        try { if (started) recorder.stop() } catch (_: Exception) { }
        finally { recorder.release(); surface.release(); file.delete() }
    }
}
