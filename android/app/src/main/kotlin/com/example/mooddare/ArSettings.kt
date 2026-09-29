package com.example.mooddare

/** Every look explicitly replaces the AR setting, so overlays cannot leak between lenses. */
internal data class ArSettings(val strength: Float = 0f, val effect: Int = 0) {
    val active: Boolean get() = effect in 1..4 && strength > 0f
    companion object {
        fun fromArguments(arguments: Map<*, *>): ArSettings {
            val effect = when (arguments["arEffect"]) {
                "heart_halo" -> 1
                "purple_shades" -> 2
                "butterflies" -> 3
                "mood_companion" -> 4
                else -> return ArSettings()
            }
            val amount = (arguments["arStrength"] as? Number)?.toFloat() ?: 0f
            return ArSettings(if (amount.isFinite()) amount.coerceIn(0f, 1f) else 0f, effect)
        }
    }
}
