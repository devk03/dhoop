package com.noop.analytics

import com.noop.data.EventRow
import com.noop.data.HrSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SleepWearEvidenceTest {
    private fun dense(lo: Long, hi: Long, bpm: Int = 60) = (lo..hi).map { it to bpm }

    @Test fun sustainedEvidenceMatchesStandaloneSwiftOracle() {
        val cases = listOf(
            emptyList(), dense(1, 60), dense(1, 61), dense(1, 61).reversed(),
            List(500) { 1L to 60 }, (1L..181L step 5).map { it to 60 },
            dense(1, 30) + dense(40, 101), dense(1, 30) + (31L to 0) + dense(32, 100),
            dense(1, 100) + (31L to 0), dense(1, 61, 29), dense(1, 61, 221),
            dense(1, 61, 30), dense(1, 61, 220), dense(1, 100).filter { it.first % 5 != 0L },
            dense(1, 30) + dense(35, 65), dense(1, 30) + dense(36, 65),
            dense(1, 61).filter { it.first !in (3L..47L step 4) },
            dense(1, 61).filter { it.first !in (3L..51L step 4) },
        )
        // Verbatim stdout from swiftc -O SleepWearEvidence.swift main.swift over these cases.
        val oracle = "null,null,1,1,null,null,40,32,32,null,null,1,1,1,1,null,1,null"
        assertEquals(oracle, cases.joinToString(",") { SleepWearEvidence.confirmedWearStart(it, 0, 500)?.toString() ?: "null" })
        assertNull(SleepWearEvidence.confirmedWearStart(dense(1, 100), 0, 60))
        assertEquals(31L, SleepWearEvidence.confirmedWearStart(dense(1, 100), 30, 100))
    }
    @Test fun laterEventsDoNotEraseEarlierSustainedWear() {
        fun event(ts: Long, kind: String) = EventRow("test", ts, kind, "{}")
        val hr = dense(1, 80).map { HrSample("test", it.first, it.second) }
        val off = event(0, "WRIST_OFF(10)")
        assertEquals(listOf(0L to 1L), AnalyticsEngine.offWristIntervals(listOf(off), 500, hr))
        assertEquals(listOf(0L to 500L), AnalyticsEngine.offWristIntervals(listOf(off), 500))
        assertEquals(listOf(0L to 1L, 100L to 500L), AnalyticsEngine.offWristIntervals(listOf(event(100, "WRIST_OFF(10)"), off), 500, hr))
        assertEquals(listOf(0L to 1L), AnalyticsEngine.offWristIntervals(listOf(off, event(300, "WRIST_ON(9)")), 500, hr))
        assertEquals(listOf(0L to 300L), AnalyticsEngine.offWristIntervals(listOf(off, event(300, "WRIST_ON(9)")), 500))
    }

    @Test fun cutoffTiesAndHalfOpenIntervalsMatchSwiftOracle() {
        val hr = dense(1, 61)
        fun spans(events: List<Pair<Long, Boolean>>, through: Long, readings: List<Pair<Long, Int>> = emptyList()) =
            SleepWearEvidence.offWristIntervals(events, readings, through).joinToString(",") { "${it.first}:${it.second}" }
        assertEquals("0:100", spans(listOf(0L to true, 200L to false), 100))
        assertEquals(spans(listOf(0L to true), 100, hr), spans(listOf(0L to true, 200L to true), 100, hr))
        assertEquals("0:100", spans(listOf(0L to true, 0L to false), 100))
        assertEquals("0:100", spans(listOf(0L to false, 0L to true, 0L to true), 100))
        assertEquals("0:61", spans(listOf(0L to true, 61L to false), 100, hr))
        assertEquals("0:1", spans(listOf(0L to true, 62L to false), 100, hr))
        assertEquals("0:1,100:200", spans(listOf(0L to true, 100L to true, 200L to false), 500, hr))
        assertEquals("0:200", spans(listOf(0L to true, 100L to true, 200L to false), 500))
    }
}
