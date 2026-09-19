package com.example.mooddare

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** Normalized, unmirrored contours with stable sample counts for temporal filtering. */
internal class FaceGeometry private constructor(val points: FloatArray) {
    fun polygon(index: Int): FloatArray = points.copyOfRange(index * STRIDE, (index + 1) * STRIDE)
    fun blend(target: FaceGeometry, amount: Float) = FaceGeometry(
        FloatArray(points.size) { points[it] + (target.points[it] - points[it]) * amount })

    fun bounds(): FloatArray {
        val face = polygon(FACE)
        val xs = face.indices.filter { it % 2 == 0 }.map { face[it] }
        val ys = face.indices.filter { it % 2 != 0 }.map { face[it] }
        return floatArrayOf(xs.min(), ys.min(), xs.max() - xs.min(), ys.max() - ys.min())
    }

    /** A mesh must belong to the same observed face, not a nearby bystander. */
    fun matches(face: FloatArray): Boolean {
        if (!FaceStabilizer.valid(face)) return false
        val b = bounds()
        val overlap = max(0f, min(b[0] + b[2], face[0] + face[2]) - max(b[0], face[0])) *
            max(0f, min(b[1] + b[3], face[1] + face[3]) - max(b[1], face[1]))
        val union = b[2] * b[3] + face[2] * face[3] - overlap
        if (union <= 0f || overlap / union < .35f) return false
        val lips = polygon(OUTER_LIPS)
        val mouthX = lips.indices.filter { it % 2 == 0 }.map { lips[it] }.average().toFloat()
        val mouthY = lips.indices.filter { it % 2 != 0 }.map { lips[it] }.average().toFloat()
        return abs(mouthX - face[8]) < face[2] * .25f && abs(mouthY - face[9]) < face[3] * .2f
    }

    companion object {
        const val FACE = 0; const val LEFT_EYE = 1; const val RIGHT_EYE = 2
        const val LEFT_BROW = 3; const val RIGHT_BROW = 4
        const val OUTER_LIPS = 5; const val INNER_LIPS = 6
        const val SAMPLES = 32
        const val STRIDE = SAMPLES * 2

        fun create(polygons: List<FloatArray>): FaceGeometry? {
            if (polygons.size != 7) return null
            val sampled = polygons.map { resample(it) ?: return null }
            val face = sampled[FACE]
            var area = 0f
            for (i in 0 until SAMPLES) {
                val next = (i + 1) % SAMPLES
                area += face[i * 2] * face[next * 2 + 1] - face[next * 2] * face[i * 2 + 1]
            }
            if (abs(area) < .01f) return null
            val geometry = FaceGeometry(sampled.flatMap { it.toList() }.toFloatArray())
            val b = geometry.bounds()
            if (b[2] < .04f || b[3] < .04f || b[2] > 1.5f || b[3] > 1.5f) return null
            for (polygon in sampled.drop(1)) {
                for (i in polygon.indices step 2) {
                    if (polygon[i] !in (b[0] - b[2] * .1f)..(b[0] + b[2] * 1.1f) ||
                        polygon[i + 1] !in (b[1] - b[3] * .1f)..(b[1] + b[3] * 1.1f)) return null
                }
            }
            return geometry
        }

        // Pair two open contour curves regardless of their endpoint direction.
        fun join(a: FloatArray, b: FloatArray): FloatArray {
            if (a.size < 4 || b.size < 4 || a.size % 2 != 0 || b.size % 2 != 0) return floatArrayOf()
            fun distance(i: Int) = hypot(a[a.size - 2] - b[i], a.last() - b[i + 1])
            val tail = if (distance(0) <= distance(b.size - 2)) b else
                b.indices.step(2).reversed().flatMap { listOf(b[it], b[it + 1]) }.toFloatArray()
            return a + tail
        }

        private fun resample(p: FloatArray): FloatArray? {
            if (p.size < 6 || p.size % 2 != 0 || p.any { !it.isFinite() || it !in -.5f..1.5f }) return null
            val count = p.size / 2
            val lengths = FloatArray(count) { i ->
                val next = (i + 1) % count
                hypot(p[next * 2] - p[i * 2], p[next * 2 + 1] - p[i * 2 + 1])
            }
            val perimeter = lengths.sum()
            if (perimeter <= .0001f) return null
            var edge = 0; var passed = 0f
            val result = FloatArray(STRIDE)
            for (i in 0 until SAMPLES) {
                val position = perimeter * i / SAMPLES
                while (edge < count - 1 && passed + lengths[edge] <= position) { passed += lengths[edge]; edge++ }
                val t = if (lengths[edge] > 0f) (position - passed) / lengths[edge] else 0f
                val next = (edge + 1) % count
                result[2 * i] = p[2 * edge] + (p[2 * next] - p[2 * edge]) * t
                result[2 * i + 1] = p[2 * edge + 1] + (p[2 * next + 1] - p[2 * edge + 1]) * t
            }
            return result
        }
    }
}
