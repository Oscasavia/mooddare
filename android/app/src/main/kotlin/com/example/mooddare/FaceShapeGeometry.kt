package com.example.mooddare

import kotlin.math.hypot
import kotlin.math.max

/** Shape guides in image-height units, aligned to the eye line before mirroring/cropping. */
internal class FaceShapeGeometry private constructor(
    val axis: FloatArray, val eyes: FloatArray, val eyeStrength: FloatArray,
    val jaw: FloatArray, val jawShift: FloatArray
) {
    companion object {
        fun create(geometry: FaceGeometry, aspect: Float): FaceShapeGeometry? {
            if (!aspect.isFinite() || aspect <= 0f) return null
            fun points(index: Int) = geometry.polygon(index).toList().chunked(2)
                .map { floatArrayOf(it[0] * aspect, it[1]) }
            fun center(p: List<FloatArray>) = floatArrayOf(
                p.map { it[0] }.average().toFloat(), p.map { it[1] }.average().toFloat())
            val contours = listOf(points(FaceGeometry.LEFT_EYE), points(FaceGeometry.RIGHT_EYE))
                .sortedBy { center(it)[0] }
            val centers = contours.map { center(it) }
            val dx = centers[1][0] - centers[0][0]; val dy = centers[1][1] - centers[0][1]
            val gap = hypot(dx, dy)
            if (gap < .015f) return null
            val axis = floatArrayOf(dx / gap, dy / gap)
            fun local(p: FloatArray) = floatArrayOf(p[0] * axis[0] + p[1] * axis[1],
                -p[0] * axis[1] + p[1] * axis[0])
            val eyes = FloatArray(8); val strength = FloatArray(2)
            for (i in 0..1) {
                val p = contours[i].map { local(it) }
                val left = p.minOf { it[0] }; val right = p.maxOf { it[0] }
                val top = p.minOf { it[1] }; val bottom = p.maxOf { it[1] }
                val width = right - left; val height = bottom - top
                if (width < gap * .15f || width > gap * .95f) return null
                eyes[i * 4] = (left + right) * .5f; eyes[i * 4 + 1] = (top + bottom) * .5f
                eyes[i * 4 + 2] = width * .85f
                eyes[i * 4 + 3] = max(height * 1.1f, width * .42f)
                // Close/wink naturally: do not enlarge a nearly closed eyelid.
                val open = ((height / width - .08f) / .14f).coerceIn(0f, 1f)
                strength[i] = open * open * (3f - 2f * open)
            }
            val oval = points(FaceGeometry.FACE).map { local(it) }
            val eyeY = (eyes[1] + eyes[5]) * .5f
            val chinY = oval.maxOf { it[1] }
            val faceWidth = oval.maxOf { it[0] } - oval.minOf { it[0] }
            val lowerHeight = chinY - eyeY
            if (lowerHeight < gap * .5f || faceWidth < gap) return null
            val jaw = FloatArray(16); val shift = FloatArray(4)
            for (level in 0..1) {
                val y = eyeY + lowerHeight * (if (level == 0) .46f else .76f)
                val crossings = oval.indices.mapNotNull { i ->
                    val a = oval[i]; val b = oval[(i + 1) % oval.size]
                    if ((a[1] > y) == (b[1] > y)) null
                    else a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1])
                }
                if (crossings.size < 2) return null
                val left = crossings.min(); val right = crossings.max()
                if (right - left < faceWidth * .2f) return null
                for (side in 0..1) {
                    val i = level * 2 + side
                    jaw[i * 4] = if (side == 0) left else right
                    jaw[i * 4 + 1] = y
                    jaw[i * 4 + 2] = (right - left) * .24f
                    jaw[i * 4 + 3] = lowerHeight * .34f
                    shift[i] = (if (side == 0) -1f else 1f) * (right - left) * .035f
                }
            }
            return FaceShapeGeometry(axis, eyes, strength, jaw, shift)
        }
    }
}
