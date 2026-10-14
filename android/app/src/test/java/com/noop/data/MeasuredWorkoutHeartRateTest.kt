package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.sql.Connection
import java.sql.DriverManager

class MeasuredWorkoutHeartRateTest {
    private fun fixture(): Connection = DriverManager.getConnection("jdbc:sqlite::memory:").apply {
        createStatement().use {
            it.execute("CREATE TABLE hrSample(deviceId TEXT, ts INTEGER, bpm INTEGER, synced INTEGER)")
            it.execute("CREATE TABLE ppgHrSample(deviceId TEXT, ts INTEGER, bpm REAL)")
            it.execute("INSERT INTO hrSample VALUES ('a',1000,60,0),('a',1001,120,0),('a',1002,150,0),('b',1000,200,0),('a',1003,0,0)")
            it.execute("INSERT INTO ppgHrSample VALUES ('a',1004,180)")
        }
    }

    private fun stats(db: Connection, from: Long, to: Long): String =
        db.prepareStatement(MEASURED_WORKOUT_HR_STATS_SQL).use { sql ->
            sql.setString(1, "a"); sql.setLong(2, from); sql.setLong(3, to)
            sql.executeQuery().use { rows ->
                rows.next()
                "${rows.getLong(1)}|${rows.getString(2)}|${rows.getString(3)}"
            }
        }

    @Test fun matchesSwiftOracleForConsecutiveSetWindows() {
        fixture().use { db ->
            // Verbatim Swift WhoopStore output for this fixture and these two boundaries.
            assertEquals("MeasuredWorkoutHR oracle: 2|90.0|120 ; 1|150.0|150",
                "MeasuredWorkoutHR oracle: ${stats(db, 1000, 1002)} ; ${stats(db, 1002, 1004)}")
            assertEquals("0|null|null", stats(db, 1004, 1005)) // Optical-only interval is unavailable.
            assertEquals("0|null|null", stats(db, 1002, 1000))
        }
    }

    @Test fun negativeAndZeroLimitsNeverTurnIntoUnlimitedReads() {
        fixture().use { db ->
            val counts = listOf(-1, 0, 1, 10).map { limit ->
                db.prepareStatement(MEASURED_WORKOUT_HR_SAMPLES_SQL).use { sql ->
                    sql.setString(1, "a"); sql.setLong(2, 1000); sql.setLong(3, 1005); sql.setInt(4, limit)
                    sql.executeQuery().use { rows ->
                        var count = 0
                        while (rows.next()) count++
                        count
                    }
                }
            }
            assertEquals(listOf(0, 0, 1, 3), counts)
        }
    }
}
