package com.noop.analytics

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class AlarmOccurrencePlannerTest {
    @Test fun swiftDSTOracle() {
        // Verbatim standalone Swift oracle output for the three cases below.
        val expected = """1772964000,1773567000
1793521800,1794130200
1791900000,1791986400"""
        val cases = listOf(Triple("2026-03-08T09:00:00Z",150,setOf(1)),
            Triple("2026-11-01T07:00:00Z",90,setOf(1)),
            Triple("2026-10-13T05:00:00Z",420,setOf(2,3,4,5,6)))
        val actual = cases.joinToString("\n") { (stamp, minute, days) ->
            AlarmOccurrencePlanner.dates(AlarmScheduleRule(minute,days),Instant.parse(stamp).epochSecond,
                ZoneId.of("America/Los_Angeles"),2).joinToString(",")
        }
        assertEquals(expected, actual)
        assertTrue(AlarmOccurrencePlanner.dates(AlarmScheduleRule(0),1000,ZoneId.of("UTC")).isEmpty())
    }
}
