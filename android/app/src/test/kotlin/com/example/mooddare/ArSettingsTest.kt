package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test

class ArSettingsTest {
    @Test fun missingUnknownAndMalformedEffectsCannotEnableAnOverlay() {
        for (args in listOf(emptyMap<String, Any>(), mapOf("arEffect" to "unknown", "arStrength" to 1),
            mapOf("arEffect" to "heart_halo", "arStrength" to "invalid"))) {
            assertFalse(ArSettings.fromArguments(args).active)
        }
    }
    @Test fun intensityIsFiniteBoundedAndZeroDisablesTracking() {
        for ((input, expected) in listOf(Float.NaN to 0f, Float.POSITIVE_INFINITY to 0f,
            -1f to 0f, 2f to 1f, .65f to .65f)) {
            val value = ArSettings.fromArguments(mapOf("arEffect" to "heart_halo", "arStrength" to input))
            assertEquals(expected, value.strength, 0f)
            assertEquals(expected > 0, value.active)
        }
    }
}
