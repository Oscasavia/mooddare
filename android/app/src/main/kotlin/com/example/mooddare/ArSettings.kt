package com.example.mooddare

/** Every look explicitly replaces the AR setting, so overlays cannot leak between lenses. */
internal data class ArSettings(val strength: Float = 0f) {
    val active: Boolean get() = strength > 0f
    companion object {
        fun fromArguments(arguments: Map<*, *>): ArSettings {
            if (arguments["arEffect"] != "heart_halo") return ArSettings()
            val amount = (arguments["arStrength"] as? Number)?.toFloat() ?: 0f
            return ArSettings(if (amount.isFinite()) amount.coerceIn(0f, 1f) else 0f)
        }
    }
}
