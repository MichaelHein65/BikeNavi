package de.michaelhein.bikenavi

import org.junit.Assert.*
import org.junit.Test

class BoschDataTest {
    @Test fun ldiFieldsStayDistinctFromAbsentFields() {
        val value = BoschData.live(byteArrayOf(0x50, 0x52, 0x28, 0x64, 0x10, 0x45))
        assertEquals(82, value.battery)
        assertEquals(100, value.riderWatts)
        assertEquals(69, value.cadence)
        assertNull(value.motorWatts)
    }
    @Test fun smartphoneFramesDecodeOnlyExplicitValues() {
        val value = BoschData.smartphone(byteArrayOf(
            0x30, 0x04, 0x80.toByte(), 0x88.toByte(), 0x08, 0x57,
            0x30, 0x04, 0x98.toByte(), 0x09, 0x08, 0x03))
        assertEquals(87, value.battery)
        assertEquals(3, value.assistMode)
        assertNull(value.riderWatts)
    }
}
