package com.example.mooddare

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

internal data class FaceObservation(
    val id: Int?, val area: Float, val points: FloatArray?,
    val pitch: Float = 0f, val yaw: Float = 0f, val roll: Float = 0f,
    val geometry: FaceGeometry? = null
)

internal data class StabilizedFace(val points: FloatArray, val strength: Float, val geometry: FaceGeometry? = null)

/** Render-thread only. Coordinates are normalized to the unmirrored source. */
internal class FaceStabilizer {
    private var id: Int? = null
    private var points: FloatArray? = null
    private var previous: FloatArray? = null
    private var measuredAt = 0L
    private var updatedAt = 0L
    private var acquiredAt = 0L
    private var quality = 0f
    private var geometry: FaceGeometry? = null
    private var previousGeometry: FaceGeometry? = null

    fun reset() {
        id = null; points = null; previous = null; quality = 0f
        geometry = null; previousGeometry = null
        measuredAt = 0L; updatedAt = 0L; acquiredAt = 0L
    }

    fun update(faces: List<FaceObservation>, submitted: Long, now: Long) {
        // A delayed detector result must not move a mask onto an old location.
        if (now - submitted >= EXPIRES_MS || submitted < measuredAt) return
        val face = faces.firstOrNull { id != null && it.id == id }
            ?: faces.maxByOrNull { it.area }
        val value = face?.points
        val pose = face?.let { poseStrength(it.pitch, it.yaw, it.roll) } ?: 0f
        val old = points
        val samePerson = id == face?.id // Spatial jump guard also applies when IDs are unavailable.
        id = face?.id
        if (value == null || !valid(value) || pose <= 0f) {
            // Known loss/occlusion stops the effect immediately; do not paint a
            // cached face over a hand, background, or a different person.
            points = null; previous = null; quality = 0f
            geometry = null; previousGeometry = null
            measuredAt = submitted
            return
        }
        val motion = if (old == null) 1f else value.indices.maxOf { i ->
            abs(value[i] - old[i]) / max(.01f, old[if (i % 2 == 0) 2 else 3])
        }
        val restart = old == null || !samePerson || submitted - measuredAt >= EXPIRES_MS || motion > .45f
        if (restart) {
            points = value.copyOf(); previous = points
            geometry = face.geometry; previousGeometry = geometry
            acquiredAt = now
        } else {
            // Suppress small jitter but follow deliberate movement promptly.
            // Scale by elapsed time so slow detectors do not add more lag.
            val base = .22f + .66f * (motion / .08f).coerceIn(0f, 1f)
            val alpha = 1f - (1f - base).pow((submitted - measuredAt).coerceIn(1, 250) / 100f)
            val sampled = sample(now)
            previous = sampled?.points ?: old
            previousGeometry = sampled?.geometry
            points = FloatArray(value.size) { old!![it] + (value[it] - old[it]) * alpha }
            geometry = face.geometry?.let { geometry?.blend(it, alpha) ?: it }
            if (geometry == null) previousGeometry = null
        }
        quality = pose
        measuredAt = submitted
        updatedAt = now
    }

    fun sample(now: Long): StabilizedFace? {
        val target = points ?: return null
        val age = now - measuredAt
        if (age >= EXPIRES_MS) return null
        val confidence = quality * ease((now - acquiredAt) / 150f) *
            (1f - ease((age - 160) / 100f))
        val blend = ease((now - updatedAt) / 35f)
        val from = previous ?: target
        val shape = geometry?.let { previousGeometry?.blend(it, blend) ?: it }
        return StabilizedFace(FloatArray(target.size) { from[it] + (target[it] - from[it]) * blend }, confidence, shape)
    }

    companion object {
        const val EXPIRES_MS = 260L
        private fun ease(value: Float): Float {
            val t = value.coerceIn(0f, 1f)
            return t * t * (3f - 2f * t)
        }
        fun poseStrength(pitch: Float, yaw: Float, roll: Float): Float {
            if (!pitch.isFinite() || !yaw.isFinite() || !roll.isFinite()) return 0f
            return min(1f - ease((abs(pitch) - 12f) / 13f),
                min(1f - ease((abs(yaw) - 12f) / 13f), 1f - ease((abs(roll) - 8f) / 12f)))
        }
        fun valid(p: FloatArray): Boolean {
            if (p.size != 12 || p.any { !it.isFinite() } || p[2] <= .04f || p[3] <= .04f || p[2] > 1.5f || p[3] > 1.5f) return false
            // Reject malformed/missing landmarks instead of warping arbitrary pixels.
            for (i in 4..10 step 2) {
                if (p[i] !in (p[0] - p[2] * .1f)..(p[0] + p[2] * 1.1f) ||
                    p[i + 1] !in (p[1] - p[3] * .1f)..(p[1] + p[3] * 1.1f)) return false
            }
            val eyeGap = abs(p[4] - p[6]) / p[2]
            val eyeY = (p[5] + p[7]) * .5f
            return eyeGap in .18f.. .85f && abs(p[5] - p[7]) / p[3] < .25f &&
                p[9] > eyeY + p[3] * .12f && p[11] > eyeY
        }
    }
}
