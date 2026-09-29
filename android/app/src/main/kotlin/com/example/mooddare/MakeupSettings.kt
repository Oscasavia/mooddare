package com.example.mooddare

/** Shared by preview, stills and video. Old presets retain their Rosy blend. */
internal data class MakeupSettings(
    val lips: Float = 0f,
    val blush: Float = 0f,
    val shade: String = "rose"
) {
    val active: Boolean get() = lips > 0f || blush > 0f
    val color: FloatArray = when (shade) {
        "red" -> floatArrayOf(191f / 255, 36f / 255, 51f / 255)
        "berry" -> floatArrayOf(140f / 255, 54f / 255, 94f / 255)
        "peach" -> floatArrayOf(217f / 255, 120f / 255, 96f / 255)
        else -> floatArrayOf(.76f, .24f, .36f)
    }

    companion object {
        private fun bounded(value: Any?): Float {
            val number = (value as? Number)?.toFloat() ?: return 0f
            return if (number.isFinite()) number.coerceIn(0f, 1f) else 0f
        }

        fun fromArguments(args: Map<*, *>): MakeupSettings {
            val legacy = bounded(args["makeup"])
            return MakeupSettings(
                if (args.containsKey("lipIntensity")) bounded(args["lipIntensity"]) else legacy,
                if (args.containsKey("blushIntensity")) bounded(args["blushIntensity"]) else legacy,
                (args["lipShade"] as? String)?.takeIf {
                    it in listOf("rose", "red", "berry", "peach")
                } ?: "rose"
            )
        }
    }
}
