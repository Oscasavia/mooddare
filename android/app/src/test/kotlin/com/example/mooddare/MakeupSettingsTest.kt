package com.example.mooddare

import org.junit.Assert.*
import org.junit.Test

class MakeupSettingsTest {
    @Test fun rosyAndOldPresetsKeepTheirAppearance() {
        val rosy = MakeupSettings.fromArguments(mapOf("makeup" to .65))
        assertEquals(.65f, rosy.lips, 0f)
        assertEquals(.65f, rosy.blush, 0f)
        assertArrayEquals(floatArrayOf(.76f, .24f, .36f), rosy.color, 0f)
        assertFalse(MakeupSettings.fromArguments(emptyMap<String, Any>()).active)
    }

    @Test fun explicitAmountsOverrideLegacyAndCanDisableEitherEffect() {
        val lips = MakeupSettings.fromArguments(mapOf("makeup" to 1, "lipIntensity" to .8,
            "blushIntensity" to 0, "lipShade" to "red"))
        assertTrue(lips.active)
        assertEquals(.8f, lips.lips, 0f)
        assertEquals(0f, lips.blush, 0f)
        val blush = MakeupSettings.fromArguments(mapOf("lipIntensity" to 0, "blushIntensity" to .3))
        assertTrue(blush.active)
        assertEquals(0f, blush.lips, 0f)
        assertEquals(.3f, blush.blush, 0f)
    }

    @Test fun invalidInputsNeverReachShaderAsNanOrUnboundedValues() {
        for (bad in listOf(null, "red", Float.NaN, Float.POSITIVE_INFINITY, -1)) {
            val look = MakeupSettings.fromArguments(mapOf("lipIntensity" to bad, "blushIntensity" to bad,
                "lipShade" to "unknown"))
            assertFalse(look.active)
            assertEquals("rose", look.shade)
        }
        val max = MakeupSettings.fromArguments(mapOf("lipIntensity" to 2, "blushIntensity" to 3))
        assertEquals(1f, max.lips, 0f)
        assertEquals(1f, max.blush, 0f)
    }

    @Test fun paletteHasDistinctBoundedColorsAndChangingShadePreservesAmounts() {
        val colors = listOf("rose", "red", "berry", "peach").map { shade ->
            val look = MakeupSettings.fromArguments(mapOf("lipShade" to shade, "lipIntensity" to .7,
                "blushIntensity" to .2))
            assertEquals(shade, look.shade)
            assertEquals(.7f, look.lips, 0f)
            assertEquals(.2f, look.blush, 0f)
            assertTrue(look.color.all { it.isFinite() && it in 0f..1f })
            look.color.toList()
        }
        assertEquals(4, colors.toSet().size)
    }
}
