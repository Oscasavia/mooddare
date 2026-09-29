package com.example.mooddare

/** Bounded, render-thread-only timing summary. No images or face coordinates. */
internal class FrameTimingWindow(private val windowNanos: Long = 5_000_000_000L) {
    data class Report(val frames: Int, val fps: Double, val averageMs: Double,
        val maximumMs: Double, val slowFrames: Int, val faceFrames: Int, val meshFrames: Int)
    private var started: Long? = null
    private var frames = 0
    private var total = 0L
    private var maximum = 0L
    private var slow = 0
    private var faces = 0
    private var meshes = 0

    fun record(now: Long, elapsed: Long, face: Boolean, mesh: Boolean): Report? {
        if (elapsed < 0) return null
        val first = started
        if (first == null || now < first) {
            started = now; frames = 0; total = 0; maximum = 0; slow = 0; faces = 0; meshes = 0
        }
        frames++; total += elapsed; maximum = maxOf(maximum, elapsed)
        if (elapsed > 33_333_333L) slow++
        if (face) faces++
        if (mesh) meshes++
        val duration = now - started!!
        if (duration < windowNanos) return null
        val report = Report(frames, (frames - 1) * 1_000_000_000.0 / duration,
            total.toDouble() / frames / 1_000_000, maximum / 1_000_000.0, slow, faces, meshes)
        started = null
        return report
    }
}
