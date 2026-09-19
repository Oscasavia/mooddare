package com.example.mooddare

import kotlin.math.ceil
import kotlin.math.floor

/** Crop coordinates are always in the upright, unmirrored still image. */
internal data class PhotoMeshRegion(val x: Int, val y: Int, val width: Int, val height: Int) {
    fun normalized(imageWidth: Int, imageHeight: Int) = floatArrayOf(
        x.toFloat() / imageWidth, y.toFloat() / imageHeight,
        width.toFloat() / imageWidth, height.toFloat() / imageHeight)

    companion object {
        fun around(face: FloatArray, imageWidth: Int, imageHeight: Int): PhotoMeshRegion {
            require(imageWidth > 0 && imageHeight > 0 && FaceStabilizer.valid(face))
            val left = floor((face[0] - face[2] * .35f) * imageWidth).toInt().coerceIn(0, imageWidth - 1)
            val top = floor((face[1] - face[3] * .25f) * imageHeight).toInt().coerceIn(0, imageHeight - 1)
            val right = ceil((face[0] + face[2] * 1.35f) * imageWidth).toInt().coerceIn(left + 1, imageWidth)
            val bottom = ceil((face[1] + face[3] * 1.25f) * imageHeight).toInt().coerceIn(top + 1, imageHeight)
            return PhotoMeshRegion(left, top, right - left, bottom - top)
        }
    }
}
