package com.noop.data

/** Used by the Room DAO and plain-SQL oracle tests; statistics describe observed rows only. */
const val MEASURED_WORKOUT_HR_STATS_SQL =
    "SELECT COUNT(*) AS n, AVG(bpm) AS avg, MAX(bpm) AS max FROM hrSample " +
        "WHERE deviceId = :deviceId AND ts >= :from AND ts < :toExclusive AND bpm > 0"

const val MEASURED_WORKOUT_HR_SAMPLES_SQL =
    "SELECT * FROM hrSample WHERE deviceId = :deviceId AND ts >= :from AND ts < :toExclusive " +
        "AND bpm > 0 ORDER BY ts LIMIT MAX(0, :limit)"
