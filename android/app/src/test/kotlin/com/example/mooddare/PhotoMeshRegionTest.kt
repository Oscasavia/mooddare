package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test

class PhotoMeshRegionTest {
    private fun face(x: Float, y: Float) = floatArrayOf(x, y, .4f, .6f,
        x + .11f, y + .22f, x + .29f, y + .22f,
        x + .2f, y + .47f, x + .2f, y + .34f)

    @Test fun paddedCropIncludesFaceWithoutLeavingImage() {
        for ((x, y) in listOf(0f to 0f, .25f to .15f, .6f to .4f)) {
            val region = PhotoMeshRegion.around(face(x, y), 1080, 1440)
            assertTrue(region.x >= 0 && region.y >= 0)
            assertTrue(region.x + region.width <= 1080)
            assertTrue(region.y + region.height <= 1440)
            assertTrue(region.x <= x * 1080)
            assertTrue(region.y <= y * 1440)
            assertTrue(region.x + region.width >= (x + .4f) * 1080 - 1)
            assertTrue(region.y + region.height >= (y + .6f) * 1440 - 1)
        }
    }

    @Test fun normalizedCropMapsLocalLandmarksBackToFullPhoto() {
        val region = PhotoMeshRegion(200, 300, 600, 900)
        val bounds = region.normalized(1000, 1500)
        assertArrayEquals(floatArrayOf(.2f, .2f, .6f, .6f), bounds, .0001f)
        assertEquals(.5f, bounds[0] + .5f * bounds[2], .0001f)
        assertEquals(.5f, bounds[1] + .5f * bounds[3], .0001f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidFaceCannotBecomeADetectorCrop() {
        PhotoMeshRegion.around(FloatArray(12), 1080, 1440)
    }
}
