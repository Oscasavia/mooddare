package com.example.mooddare

/** Mouth opening in the same physical eye-line frame as AR placement. */
internal object ArFaceMetrics {
    fun mouthOpenness(geometry: FaceGeometry, aspect: Float, axis: FloatArray): Float {
        if (!aspect.isFinite() || aspect <= 0f || axis.size != 2 || axis.any { !it.isFinite() }) return 0f
        fun span(contour: Int, vertical: Boolean): Float {
            val p = geometry.polygon(contour)
            var low = Float.POSITIVE_INFINITY; var high = Float.NEGATIVE_INFINITY
            for (i in p.indices step 2) {
                val x = p[i] * aspect; val y = p[i + 1]
                val v = if (vertical) -x * axis[1] + y * axis[0] else x * axis[0] + y * axis[1]
                low = minOf(low, v); high = maxOf(high, v)
            }
            return high - low
        }
        val width = span(FaceGeometry.OUTER_LIPS, false)
        if (width < .01f) return 0f
        val ratio = span(FaceGeometry.INNER_LIPS, true) / width
        val t = ((ratio - .08f) / .25f).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }
}
