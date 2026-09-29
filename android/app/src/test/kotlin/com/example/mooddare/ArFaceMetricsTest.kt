package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class ArFaceMetricsTest {
    private fun rect(x: Float, y: Float, w: Float, h: Float) = floatArrayOf(x,y,x+w,y,x+w,y+h,x,y+h)
    private fun contours(open: Float) = listOf(rect(.2f,.1f,.6f,.8f),
        rect(.3f,.3f,.1f,.05f),rect(.6f,.3f,.1f,.05f),rect(.28f,.25f,.12f,.02f),rect(.58f,.25f,.12f,.02f),
        rect(.35f,.55f,.3f,.18f),rect(.4f,.6f,.2f,open))
    @Test fun mouthClosedIsQuietAndOpeningProducesAContinuousBoundedReaction() {
        val values = listOf(.005f,.04f,.07f,.12f).map {
            ArFaceMetrics.mouthOpenness(FaceGeometry.create(contours(it))!!,1f,floatArrayOf(1f,0f))
        }
        assertEquals(0f,values.first(),.001f); assertEquals(1f,values.last(),.001f)
        for (i in 1..3) assertTrue(values[i] > values[i-1])
    }
    @Test fun reactionIsInvariantToTranslationScaleAndHeadTilt() {
        val original = FaceGeometry.create(contours(.07f))!!
        val expected = ArFaceMetrics.mouthOpenness(original,1f,floatArrayOf(1f,0f))
        val angle=.14f; val c=cos(angle); val s=sin(angle)
        val moved = contours(.07f).map { p -> FloatArray(p.size).also { out ->
            for (i in p.indices step 2) {
                val x=(p[i]-.5f)*.8f; val y=(p[i+1]-.5f)*.8f
                out[i]=.55f+x*c-y*s; out[i+1]=.52f+x*s+y*c
            }
        } }
        assertEquals(expected,ArFaceMetrics.mouthOpenness(FaceGeometry.create(moved)!!,1f,floatArrayOf(c,s)),.005f)
        assertEquals(0f,ArFaceMetrics.mouthOpenness(original,Float.NaN,floatArrayOf(1f,0f)),0f)
    }
}
