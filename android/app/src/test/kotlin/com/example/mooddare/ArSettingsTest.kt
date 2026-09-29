package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test

class ArSettingsTest {
    @Test fun eachEffectReplacesThePreviousKindAndLegacyHaloKeepsItsValue() {
        for ((index, id) in listOf("heart_halo", "purple_shades", "butterflies", "mood_companion").withIndex()) {
            val value = ArSettings.fromArguments(mapOf("arEffect" to id, "arStrength" to .7))
            assertEquals(index + 1, value.effect)
            assertTrue(value.active)
            assertEquals(.7f, value.strength, .001f)
        }
        assertEquals(0, ArSettings.fromArguments(mapOf("arEffect" to "none", "arStrength" to 1)).effect)
    }
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
