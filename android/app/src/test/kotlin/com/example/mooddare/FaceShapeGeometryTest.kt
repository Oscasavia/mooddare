package com.example.mooddare

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class FaceShapeGeometryTest {
    private fun oval(x: Float, y: Float, rx: Float, ry: Float) = FloatArray(64) { i ->
        val t = (i / 2) * 2 * Math.PI / 32
        if (i % 2 == 0) x + rx * cos(t).toFloat() else y + ry * sin(t).toFloat()
    }
    private fun contours(closedLeft: Boolean = false) = listOf(
        oval(.5f, .48f, .28f, .39f),
        oval(.38f, .38f, .07f, if (closedLeft) .002f else .025f), oval(.62f, .38f, .07f, .025f),
        oval(.38f, .3f, .08f, .015f), oval(.62f, .3f, .08f, .015f),
        oval(.5f, .66f, .09f, .04f), oval(.5f, .66f, .07f, .015f))
    private fun shape(p: List<FloatArray>, aspect: Float = 1f) = FaceShapeGeometry.create(FaceGeometry.create(p)!!, aspect)!!

    @Test fun jawGuidesFollowEachSideAndLeaveTheCenterClear() {
        val s = shape(contours())
        for (i in 0..3) {
            val center = s.jaw[i * 4]; val radius = s.jaw[i * 4 + 2]
            if (i % 2 == 0) {
                assertTrue(center + radius < .5f)
                assertTrue(s.jawShift[i] < 0f)
            } else {
                assertTrue(center - radius > .5f)
                assertTrue(s.jawShift[i] > 0f)
            }
            assertTrue(abs(s.jawShift[i]) < radius * .2f)
        }
        assertTrue(s.jaw[8] > s.jaw[0]) // Jaw narrows toward the chin.
        assertTrue(s.jaw[12] < s.jaw[4])
    }

    @Test fun blinkingDisablesOnlyTheClosedEyeWithoutMovingJaw() {
        val open = shape(contours()); val wink = shape(contours(true))
        assertEquals(1f, open.eyeStrength[0], .0001f)
        assertEquals(0f, wink.eyeStrength[0], .0001f)
        assertEquals(1f, wink.eyeStrength[1], .0001f)
        assertArrayEquals(open.jaw, wink.jaw, .0001f)
        assertEquals(open.eyes[0], wink.eyes[0], .0001f)
    }

    @Test fun guidesRotateWithHeadAndRespectImageAspect() {
        val original = contours()
        val baseline = shape(original)
        val angle = .25f; val c = cos(angle); val s = sin(angle)
        // Rotation in physical coordinates, then store in a narrower image.
        val aspect = .75f
        val rotated = original.map { p -> FloatArray(p.size) { i ->
            val x = p[i / 2 * 2]; val y = p[i / 2 * 2 + 1]
            if (i % 2 == 0) (x * c - y * s) / aspect else x * s + y * c
        } }
        val result = shape(rotated, aspect)
        assertArrayEquals(floatArrayOf(c, s), result.axis, .002f)
        assertArrayEquals(baseline.eyes, result.eyes, .003f)
        // Contours are re-sampled to 32 points in normalized image space;
        // allow less than 1% of face width for that polygon approximation.
        assertArrayEquals(baseline.jaw, result.jaw, .005f)
        assertArrayEquals(baseline.jawShift, result.jawShift, .001f)
    }

    @Test fun smilingMovesLipContoursWithoutDraggingJawAnchors() {
        val p = contours().toMutableList()
        val initial = shape(p)
        p[FaceGeometry.OUTER_LIPS] = oval(.5f, .63f, .13f, .055f)
        p[FaceGeometry.INNER_LIPS] = oval(.5f, .63f, .10f, .025f)
        assertArrayEquals(initial.jaw, shape(p).jaw, .0001f)
    }

    @Test fun malformedEyeSeparationCannotCreateShapeGuides() {
        val p = contours().toMutableList(); p[2] = p[1].copyOf()
        assertNull(FaceShapeGeometry.create(FaceGeometry.create(p)!!, 1f))
        assertNull(FaceShapeGeometry.create(FaceGeometry.create(contours())!!, Float.NaN))
    }
}
