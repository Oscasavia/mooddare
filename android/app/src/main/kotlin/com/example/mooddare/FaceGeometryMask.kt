package com.example.mooddare

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path

/** Red = skin, green = lips. No color classification or skin-tone threshold. */
internal class FaceGeometryMask {
    val bitmap = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
    var bounds = floatArrayOf(0f, 0f, 1f, 1f)
        private set
    private val canvas = Canvas(bitmap)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    fun update(geometry: FaceGeometry) {
        val b = geometry.bounds()
        bounds = floatArrayOf(b[0] - b[2] * .04f, b[1] - b[3] * .04f, b[2] * 1.08f, b[3] * 1.08f)
        bitmap.eraseColor(Color.BLACK)
        fun path(index: Int): Path {
            val points = geometry.polygon(index)
            return Path().apply {
                for (i in points.indices step 2) {
                    val x = (points[i] - bounds[0]) / bounds[2] * bitmap.width
                    val y = (points[i + 1] - bounds[1]) / bounds[3] * bitmap.height
                    if (i == 0) moveTo(x, y) else lineTo(x, y)
                }
                close()
            }
        }
        paint.style = Paint.Style.FILL
        paint.color = Color.RED
        paint.maskFilter = BlurMaskFilter(2f, BlurMaskFilter.Blur.NORMAL)
        canvas.drawPath(path(FaceGeometry.FACE), paint)
        // Expand protected features slightly, then feather their edges.
        paint.color = Color.BLACK
        paint.style = Paint.Style.FILL_AND_STROKE
        paint.strokeWidth = 3f
        for (index in FaceGeometry.LEFT_EYE..FaceGeometry.OUTER_LIPS) canvas.drawPath(path(index), paint)
        paint.style = Paint.Style.FILL
        paint.color = Color.GREEN
        paint.maskFilter = null
        val lips = path(FaceGeometry.OUTER_LIPS).apply {
            fillType = Path.FillType.EVEN_ODD
            addPath(path(FaceGeometry.INNER_LIPS))
        }
        canvas.drawPath(lips, paint)
        // No tint on teeth or inside an open mouth, including the feathered boundary.
        paint.color = Color.BLACK
        paint.style = Paint.Style.FILL_AND_STROKE
        paint.strokeWidth = 4f
        canvas.drawPath(path(FaceGeometry.INNER_LIPS), paint)
    }

    fun close() = bitmap.recycle()
}
