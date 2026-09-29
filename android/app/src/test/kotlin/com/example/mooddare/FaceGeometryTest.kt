package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test

class FaceGeometryTest {
    private fun rect(x: Float, y: Float, w: Float, h: Float) =
        floatArrayOf(x, y, x + w, y, x + w, y + h, x, y + h)
    private fun polygons(dx: Float = 0f) = listOf(
        rect(.25f + dx, .15f, .4f, .6f),
        rect(.32f + dx, .35f, .08f, .04f), rect(.5f + dx, .35f, .08f, .04f),
        rect(.31f + dx, .30f, .1f, .025f), rect(.49f + dx, .30f, .1f, .025f),
        rect(.36f + dx, .58f, .18f, .08f), rect(.39f + dx, .60f, .12f, .025f))
    private fun face(dx: Float = 0f) = floatArrayOf(.25f + dx, .15f, .4f, .6f,
        .36f + dx, .37f, .54f + dx, .37f, .45f + dx, .62f, .45f + dx, .49f)

    @Test fun contoursHaveStableSamplesAndMatchOnlyTheirFace() {
        val geometry = FaceGeometry.create(polygons())!!
        assertEquals(7 * 32 * 2, geometry.points.size)
        assertTrue(geometry.matches(face()))
        assertFalse(geometry.matches(face(.3f)))
        assertArrayEquals(floatArrayOf(.25f, .15f, .4f, .6f), geometry.bounds(), .0001f)
    }

    @Test fun malformedOrOutlyingContoursAreRejected() {
        assertNull(FaceGeometry.create(emptyList()))
        for (bad in listOf(floatArrayOf(), FloatArray(8), floatArrayOf(Float.NaN, 0f, 1f, 0f, 1f, 1f), rect(1.2f, .4f, .1f, .1f))) {
            val values = polygons().toMutableList(); values[1] = bad
            assertNull(FaceGeometry.create(values))
        }
        val zeroFace = polygons().toMutableList(); zeroFace[0] = rect(.2f, .2f, .001f, .001f)
        assertNull(FaceGeometry.create(zeroFace))
    }

    @Test fun contourJoiningChoosesTheAdjacentEndpoint() {
        val upper = floatArrayOf(0f, .5f, .5f, .3f, 1f, .5f)
        val lower = floatArrayOf(0f, .5f, .5f, .7f, 1f, .5f)
        val joined = FaceGeometry.join(upper, lower)
        assertEquals(1f, joined[6], .0001f)
        assertEquals(0f, joined[joined.size - 2], .0001f)
        val reversed = floatArrayOf(1f, .5f, .5f, .7f, 0f, .5f)
        assertArrayEquals(joined, FaceGeometry.join(upper, reversed), .0001f)
    }

    @Test fun geometryFollowsTheSameTemporalBlendAndExpiresWithTheFace() {
        val tracker = FaceStabilizer()
        val original = FaceGeometry.create(polygons())!!
        tracker.update(listOf(FaceObservation(1, 1f, face(), geometry = original)), 0, 0)
        tracker.update(listOf(FaceObservation(1, 1f, face(.04f), geometry = FaceGeometry.create(polygons(.04f)))), 100, 100)
        assertEquals(.25f, tracker.sample(100)!!.geometry!!.bounds()[0], .0001f)
        val moved = tracker.sample(135)!!
        assertEquals(moved.points[0], moved.geometry!!.bounds()[0], .0001f)
        assertNull(tracker.sample(360))
        tracker.update(emptyList(), 200, 200)
        assertNull(tracker.sample(210))
    }

    @Test fun missingGeometryNeverReusesAnOldMakeupMask() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(FaceObservation(1, 1f, face(), geometry = FaceGeometry.create(polygons()))), 0, 0)
        tracker.update(listOf(FaceObservation(1, 1f, face())), 100, 100)
        assertNull(tracker.sample(135)!!.geometry)
    }

    @Test fun identityChangeResetsGeometryWithoutBlendingBetweenPeople() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(FaceObservation(1, 1f, face(), geometry = FaceGeometry.create(polygons()))), 0, 0)
        tracker.update(listOf(FaceObservation(2, 1f, face(.2f), geometry = FaceGeometry.create(polygons(.2f)))), 100, 100)
        assertEquals(.45f, tracker.sample(100)!!.geometry!!.bounds()[0], .0001f)
        assertEquals(0f, tracker.sample(100)!!.strength, .0001f)
        tracker.reset()
        assertNull(tracker.sample(150))
    }

    private fun progress(before: FaceGeometry, after: FaceGeometry, target: FaceGeometry, contour: Int): Float {
        val a = before.polygon(contour); val b = after.polygon(contour); val c = target.polygon(contour)
        var movement = 0f; var expected = 0f
        for (i in a.indices) {
            val delta = c[i] - a[i]
            movement += (b[i] - a[i]) * delta
            expected += delta * delta
        }
        return movement / expected
    }

    @Test fun talkingFollowsLipsQuicklyWithoutMovingTheFaceOrTintingWithAnOldMouthOpening() {
        val tracker = FaceStabilizer()
        val before = FaceGeometry.create(polygons())!!
        val speaking = polygons().toMutableList()
        speaking[FaceGeometry.OUTER_LIPS] = rect(.35f, .55f, .2f, .16f)
        speaking[FaceGeometry.INNER_LIPS] = rect(.39f, .58f, .12f, .10f)
        val target = FaceGeometry.create(speaking)!!
        tracker.update(listOf(FaceObservation(1, 1f, face(), geometry = before)), 0, 0)
        tracker.update(listOf(FaceObservation(1, 1f, face(), geometry = target)), 100, 100)
        val after = tracker.sample(135)!!.geometry!!
        val outer = progress(before, after, target, FaceGeometry.OUTER_LIPS)
        val inner = progress(before, after, target, FaceGeometry.INNER_LIPS)
        assertTrue("Speech must catch up faster than steady-head smoothing: $outer", outer > .7f)
        assertEquals("Inner and outer lips must remain synchronized", outer, inner, .001f)
        assertArrayEquals(before.bounds(), after.bounds(), .0001f)
        assertArrayEquals(before.polygon(FaceGeometry.LEFT_EYE), after.polygon(FaceGeometry.LEFT_EYE), .0001f)
    }

    @Test fun blinkingDoesNotWaitForHeadMovementAndDoesNotMoveTheOtherEye() {
        val before = FaceGeometry.create(polygons())!!
        val blink = polygons().toMutableList()
        blink[FaceGeometry.LEFT_EYE] = rect(.32f, .368f, .08f, .004f)
        val target = FaceGeometry.create(blink)!!
        val after = before.blendExpression(target, .22f)
        val fraction = progress(before, after, target, FaceGeometry.LEFT_EYE)
        assertTrue("Blink should respond faster than .22 steady-head smoothing: $fraction", fraction > .45f)
        assertArrayEquals(before.polygon(FaceGeometry.RIGHT_EYE), after.polygon(FaceGeometry.RIGHT_EYE), 0f)
    }

    @Test fun tinyExpressionJitterKeepsTemporalSmoothingAndTranslationStaysAligned() {
        val before = FaceGeometry.create(polygons())!!
        val jitter = polygons().toMutableList()
        jitter[FaceGeometry.OUTER_LIPS] = rect(.3605f, .58f, .18f, .08f)
        val target = FaceGeometry.create(jitter)!!
        assertEquals(.15f, progress(before, before.blendExpression(target, .15f), target, FaceGeometry.OUTER_LIPS), .001f)
        val translated = FaceGeometry.create(polygons(.04f))!!
        val blended = before.blendExpression(translated, .3f)
        for (contour in 0..6) assertEquals(.3f, progress(before, blended, translated, contour), .001f)
    }

    @Test fun settledSamplesReuseGeometryAndCoordinatesBetweenDetections() {
        val geometry = FaceGeometry.create(polygons())!!
        assertSame(geometry, geometry.blend(geometry, .5f))
        val moved = FaceGeometry.create(polygons(.04f))!!
        assertSame(moved, geometry.blend(moved, 1f))
        assertSame(geometry, geometry.blend(moved, 0f))
        val tracker = FaceStabilizer()
        tracker.update(listOf(FaceObservation(1, 1f, face(), geometry = geometry)), 0, 0)
        tracker.update(listOf(FaceObservation(1, 1f, face(.04f), geometry = moved)), 100, 100)
        val a = tracker.sample(135)!!; val b = tracker.sample(150)!!
        assertSame(a.points, b.points)
        assertSame(a.geometry, b.geometry)
    }
}
