package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LiftPhaseMetadataMigrationTest {
    @Test
    fun legacyEntitiesKeepUnknownMetadata() {
        assertNull(LiftExerciseRow(id = "e", deviceId = "d", name = "Press", createdAt = 1).parentExerciseId)
        assertNull(LiftProgramItemRow(id = "p", deviceId = "d", programId = "r", ord = 0, exercise = "Press").supersetGroupId)
        assertNull(LiftSessionRow(id = "s", deviceId = "d", startTs = 1, sport = "Strength Training").activityIntervalsJSON)
        val set = LiftSetEntity(id = "set", deviceId = "d", sessionId = "s", ord = 0, exercise = "Press", setIndex = 1)
        assertNull(set.supersetGroupId)
        assertNull(set.roundIndex)
        assertEquals(0, set.copy(supersetGroupId = "group", roundIndex = 0).roundIndex)
    }
}
