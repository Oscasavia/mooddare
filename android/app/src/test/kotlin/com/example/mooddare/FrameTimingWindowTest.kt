package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test

class FrameTimingWindowTest {
    @Test fun reportsThroughputProcessingTimeAndTrackingWithoutGrowingHistory() {
        val timing = FrameTimingWindow(100_000_000)
        assertNull(timing.record(0, 10_000_000, true, true))
        assertNull(timing.record(50_000_000, 40_000_000, true, false))
        val report = timing.record(100_000_000, 10_000_000, false, false)!!
        assertEquals(3, report.frames)
        assertEquals(20.0, report.fps, .001)
        assertEquals(20.0, report.averageMs, .001)
        assertEquals(40.0, report.maximumMs, .001)
        assertEquals(1, report.slowFrames)
        assertEquals(2, report.faceFrames)
        assertEquals(1, report.meshFrames)
        assertNull(timing.record(150_000_000, 1_000_000, false, false))
        val next = timing.record(250_000_000, 1_000_000, false, false)!!
        assertEquals(2, next.frames)
        assertEquals(0, next.slowFrames)
        assertEquals(1.0, next.averageMs, .001)
    }

    @Test fun invalidTimeDoesNotProduceNegativeOrNonfiniteMetrics() {
        val timing = FrameTimingWindow(100)
        assertNull(timing.record(1000, -1, false, false))
        assertNull(timing.record(1000, 1, false, false))
        assertNull(timing.record(100, 1, false, false))
        val report = timing.record(200, 1, false, false)!!
        assertTrue(report.fps.isFinite() && report.fps > 0)
        assertEquals(2, report.frames)
    }
}
