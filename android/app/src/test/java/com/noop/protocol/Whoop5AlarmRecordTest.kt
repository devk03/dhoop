package com.noop.protocol

import org.junit.Assert.*
import org.junit.Test

class Whoop5AlarmRecordTest {
    @Test fun swiftOracleAndUnknownZero() {
        // Verbatim stdout of standalone swiftc oracle over slots 0...7.
        val expected = """invalid
0401e0c8cd6a00002f980000000000000000071e00
0402e0c8cd6a00002f980000000000000000071e00
0403e0c8cd6a00002f980000000000000000071e00
0404e0c8cd6a00002f980000000000000000071e00
0405e0c8cd6a00002f980000000000000000071e00
0406e0c8cd6a00002f980000000000000000071e00
invalid"""
        assertEquals(expected, (0..7).joinToString("\n") { slot ->
            Whoop5AlarmRecord.standard(slot, 1791871200)?.bytes?.joinToString("") { "%02x".format(it) } ?: "invalid"
        })
        val zero = Whoop5AlarmRecord.decode(listOf(4,1) + List(19) { 0 }, 1)!!
        assertTrue(zero.isClearedCandidate)
        assertNull(Whoop5AlarmRecord.decode(List(21) { 0 }, 1))
        assertNull(Whoop5AlarmRecord.clearPayload(255))
        assertEquals(listOf(2,6), Whoop5AlarmRecord.clearPayload(6))
    }
}
