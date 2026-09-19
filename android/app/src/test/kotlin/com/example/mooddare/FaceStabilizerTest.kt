package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs

class FaceStabilizerTest {
    private fun points(dx: Float = 0f) = floatArrayOf(
        .25f + dx, .15f, .4f, .6f,
        .36f + dx, .37f, .54f + dx, .37f,
        .45f + dx, .62f, .45f + dx, .49f
    )
    private fun face(id: Int? = 1, dx: Float = 0f, area: Float = 1f) =
        FaceObservation(id, area, points(dx))

    @Test fun keepsTrackedPersonWhenAnotherFaceBecomesLarger() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face(), face(2, .25f, .8f)), 0, 0)
        tracker.update(listOf(face(), face(2, .25f, 2f)), 100, 100)
        assertEquals(.25f, tracker.sample(150)!!.points[0], .0001f)
        assertEquals(1f, tracker.sample(150)!!.strength, .0001f)
    }

    @Test fun missingLandmarksOnTrackedPersonDoNotTransferEffectToBystander() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face()), 0, 0)
        val occluded = FaceObservation(1, 1f, null)
        tracker.update(listOf(occluded, face(2, .25f, 2f)), 100, 100)
        assertNull(tracker.sample(110))
        tracker.update(listOf(occluded, face(2, .25f, 2f)), 200, 200)
        assertNull(tracker.sample(210))
    }

    @Test fun steadyFaceJitterIsReducedButLargeMovementCatchesUp() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face()), 0, 0)
        var error = 0f
        for (i in 1..20) {
            val offset = if (i % 2 == 0) .002f else -.002f
            tracker.update(listOf(face(dx = offset)), i * 100L, i * 100L)
            error += abs(tracker.sample(i * 100L + 35)!!.points[0] - .25f)
        }
        assertTrue("Reduce tiny position changes by at least half", error / 20 < .001f)
        tracker.update(listOf(face(dx = .05f)), 2100, 2100)
        assertTrue("Follow a deliberate move without a long smoothing trail", tracker.sample(2135)!!.points[0] > .29f)
    }

    @Test fun newCoordinatesInterpolateBetweenDetectorUpdates() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face()), 0, 0)
        tracker.update(listOf(face(dx = .04f)), 100, 100)
        val start = tracker.sample(100)!!.points[0]
        val middle = tracker.sample(117)!!.points[0]
        val end = tracker.sample(135)!!.points[0]
        assertEquals(.25f, start, .0001f)
        assertTrue(middle > start && middle < end)
        assertTrue(end > .28f && end < .29f)
    }

    @Test fun newIdentityAndLargeJumpNeverBlendAcrossFaces() {
        for (newId in listOf(1, 2)) {
            val tracker = FaceStabilizer()
            tracker.update(listOf(face()), 0, 0)
            tracker.update(listOf(face(newId, .25f)), 100, 100)
            assertEquals(.5f, tracker.sample(100)!!.points[0], .0001f)
            assertEquals(0f, tracker.sample(100)!!.strength, .0001f)
        }
    }

    @Test fun facesWithoutTrackingIdsCanSettleWithoutRestartingEveryFrame() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face(null)), 0, 0)
        tracker.update(listOf(face(null)), 100, 100)
        assertEquals(1f, tracker.sample(150)!!.strength, .0001f)
    }

    @Test fun staleResultsExpireAndCannotReviveOldCoordinates() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face()), 0, 0)
        assertTrue(tracker.sample(220)!!.strength in .01f.. .99f)
        assertNull(tracker.sample(260))
        tracker.update(listOf(face()), 0, 300)
        assertNull(tracker.sample(300))
        tracker.update(listOf(face(dx = .1f)), 400, 400)
        tracker.update(listOf(face()), 350, 410)
        assertEquals(.35f, tracker.sample(420)!!.points[0], .0001f)
    }

    @Test fun lostFaceStopsImmediatelyAndReacquisitionFadesIn() {
        val tracker = FaceStabilizer()
        tracker.update(listOf(face()), 0, 0)
        tracker.update(emptyList(), 100, 100)
        assertNull(tracker.sample(101))
        tracker.update(listOf(face()), 200, 200)
        assertEquals(0f, tracker.sample(200)!!.strength, .0001f)
        assertTrue(tracker.sample(275)!!.strength in .1f.. .9f)
        tracker.reset()
        assertNull(tracker.sample(276))
    }

    @Test fun poseStrengthFadesBeforeUnsupportedAngles() {
        assertEquals(1f, FaceStabilizer.poseStrength(0f, 0f, 0f), .0001f)
        assertTrue(FaceStabilizer.poseStrength(0f, 18f, 0f) in .1f.. .9f)
        assertEquals(0f, FaceStabilizer.poseStrength(0f, 25f, 0f), .0001f)
        assertEquals(0f, FaceStabilizer.poseStrength(0f, 0f, -20f), .0001f)
        assertEquals(0f, FaceStabilizer.poseStrength(Float.NaN, 0f, 0f), .0001f)
    }

    @Test fun invalidGeometryNeverReachesRenderer() {
        assertTrue(FaceStabilizer.valid(points()))
        val bad = listOf(FloatArray(12), points().apply { this[4] = Float.NaN },
            points().apply { this[9] = .1f }, points().apply { this[6] = this[4] },
            points().apply { this[10] = 5f })
        for (value in bad) {
            assertFalse(FaceStabilizer.valid(value))
            val tracker = FaceStabilizer()
            tracker.update(listOf(FaceObservation(1, 1f, value)), 0, 0)
            assertNull(tracker.sample(150))
        }
    }
}
