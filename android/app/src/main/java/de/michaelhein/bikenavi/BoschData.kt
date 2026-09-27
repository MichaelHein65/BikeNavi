package de.michaelhein.bikenavi

data class BikeMeasurement(
    val battery: Int? = null,
    val riderWatts: Int? = null,
    val motorWatts: Int? = null,
    val assistMode: Int? = null,
    val cadence: Int? = null,
    val speedKph: Double? = null
)

/** Bosch LDI V1: protobuf scalar fields documented in the iPhone implementation. */
object BoschData {
    fun live(bytes: ByteArray): BikeMeasurement {
        var offset = 0
        fun varint(): Long {
            var value = 0L
            for (i in 0..9) {
                if (offset >= bytes.size) throw IllegalArgumentException("Unvollständiges Protobuf.")
                val item = bytes[offset++].toInt() and 255
                if (i == 9 && item > 1) throw IllegalArgumentException("Varint zu lang.")
                value = value or ((item and 127).toLong() shl (i * 7))
                if (item and 128 == 0) return value
            }
            throw IllegalArgumentException("Varint zu lang.")
        }
        var result = BikeMeasurement()
        while (offset < bytes.size) {
            val tag = varint()
            val field = tag ushr 3
            val wire = tag and 7
            if (field < 1 || field > 0x1fffffff) throw IllegalArgumentException("Ungültiges Protobuf.")
            if (field in listOf(1L, 2L, 5L, 10L, 22L) && wire != 0L)
                throw IllegalArgumentException("Falsches Datenformat.")
            if (wire == 0L) {
                val value = varint()
                result = when (field) {
                    1L -> { require(value in 0..65535); result.copy(speedKph = value / 100.0) }
                    2L -> {
                        val cadence = value.toInt()
                        require(cadence in -32768..32767)
                        result.copy(cadence = cadence.takeIf { it >= 0 })
                    }
                    5L -> { require(value in 0..65535); result.copy(riderWatts = value.toInt()) }
                    10L -> { require(value in 0..100); result.copy(battery = value.toInt()) }
                    else -> result
                }
            } else {
                val length = when (wire) {
                    1L -> 8L
                    2L -> varint()
                    5L -> 4L
                    else -> throw IllegalArgumentException("Unbekanntes Datenformat.")
                }
                require(length >= 0 && length <= bytes.size - offset)
                offset += length.toInt()
            }
        }
        return result
    }

    /** Experimental notification envelope; no characteristic writes/control. */
    fun smartphone(bytes: ByteArray): BikeMeasurement {
        var offset = 0
        var result = BikeMeasurement()
        while (offset < bytes.size) {
            require(bytes.size - offset >= 4)
            val envelope = bytes[offset].toInt() and 255
            require(envelope == 0x10 || envelope == 0x30)
            val count = bytes[offset + 1].toInt() and 255
            require(count >= 2 && count <= bytes.size - offset - 2)
            val end = offset + count + 2
            val id = ((bytes[offset + 2].toInt() and 255) shl 8) or
                (bytes[offset + 3].toInt() and 255)
            if (envelope == 0x30 && id in listOf(0x8088, 0x985b, 0x985d, 0x9809)) {
                var value = 0L
                if (count > 2) {
                    require(count >= 4 && (bytes[offset + 4].toInt() and 255) == 0x08)
                    var cursor = offset + 5
                    var finished = false
                    for (i in 0..9) {
                        require(cursor < end)
                        val item = bytes[cursor++].toInt() and 255
                        if (i == 9) require(item <= 1)
                        value = value or ((item and 127).toLong() shl (i * 7))
                        if (item and 128 == 0) { finished = true; break }
                    }
                    require(finished && cursor == end)
                }
                require(value in 0..(if (id == 0x8088) 100 else if (id == 0x9809) 255 else 65535))
                result = when (id) {
                    0x8088 -> result.copy(battery = value.toInt())
                    0x985b -> result.copy(riderWatts = value.toInt())
                    0x985d -> result.copy(motorWatts = value.toInt())
                    else -> result.copy(assistMode = value.toInt())
                }
            }
            offset = end
        }
        return result
    }
}
