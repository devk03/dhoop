package com.noop.analytics

import com.noop.data.HrSample
import com.noop.data.GravitySample
import org.junit.Assert.assertEquals
import org.junit.Test

class SleepGapPreservationTest {
    @Test fun mergingUsesOnlyConnectedNeighbors() {
        fun p(start: Long, end: Long, stage: String = "sleep") = SleepStager.Period(stage, start, end)
        val cases = listOf(
            listOf(p(0,599),p(21600,26999)), listOf(p(0,5399),p(27000,27599)),
            listOf(p(0,5399),p(5400,5599,"active"),p(27000,32399)),
            listOf(p(0,5399),p(27000,27199,"active"),p(27200,32599)),
            listOf(p(0,5399),p(5400,5599,"active"),p(5600,10999)),
            listOf(p(0,599),p(1799,7198)), listOf(p(0,599),p(1800,7199)),
        )
        val expected = listOf("sleep:21600:26999", "sleep:0:5399", "sleep:0:5599,sleep:27000:32399",
            "sleep:0:5399,sleep:27000:32599", "sleep:0:10999", "sleep:0:7198", "sleep:1800:7199")
        assertEquals(expected, cases.map { SleepStager.mergePeriods(it).joinToString(",") { p -> "${p.stage}:${p.start}:${p.end}" } })
    }
    @Test fun exactMinimumDurationMatchesFragmentRescueFloor() {
        val start = 1749513600L + 2 * 3600
        val hr = (0L..3600L).map { HrSample("test", start + it, 50) }
        val gravity = hr.map { GravitySample("test", it.ts, 0.0, 0.0, 1.0) }
        val result = SleepStager.detectSleep(hr = hr, gravity = gravity)
        assertEquals(listOf(start to (start+3600)), result.map { it.start to it.end })
    }
    @Test fun hrOnlyFallbackHonorsLongSpanAndOffWristGuards() {
        val long = (0L..61200L).map { HrSample("test", it, 50) }
        assertEquals(0, SleepStager.hrOnlySessions("1970-01-01", long, emptyList(), emptyList()).size)
        val night = (0L..5400L).map { HrSample("test", it, 50) }
        assertEquals(1, SleepStager.hrOnlySessions("1970-01-01", night, emptyList(), emptyList()).size)
        assertEquals(0, SleepStager.hrOnlySessions("1970-01-01", night, emptyList(), emptyList(), wristOff = listOf(0L to 5400L)).size)
    }
    private fun hr(start: Long) = ((0L until 600L) + (21600L until 27000L)).map { HrSample("test", start + it, 50) }

    @Test fun shortFragmentCannotFillHoursWithoutReadings() {
        val result = SleepStager.hrOnlySessions("1970-01-01", hr(0), emptyList(), emptyList())
        // Swift public-boundary oracle: one [21600,26999] session; never [0,26999].
        assertEquals(listOf(21600L to 26999L), result.map { it.start to it.end })
    }
    @Test fun shortMotionFragmentCannotEraseLaterNightAcrossMissingHours() {
        val start = 1749513600L - 4 * 3600
        val hr = hr(start)
        val gravity = hr.map { GravitySample("test", it.ts, 0.0, 0.0, 1.0) }
        val result = SleepStager.detectSleep(hr = hr, gravity = gravity)
        assertEquals(listOf((start + 21600) to (start + 26999)), result.map { it.start to it.end })
    }
}
