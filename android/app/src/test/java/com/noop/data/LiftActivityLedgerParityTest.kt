package com.noop.data

import org.junit.Assert.assertEquals
import org.junit.Test

class LiftActivityLedgerParityTest {
    @Test fun boundariesMatchStandaloneSwiftOracle() {
        // Verbatim stdout from swiftc -O LiftActivityInterval.swift + oracle main (414 cases).
        val expected = listOf(
            "BBBBBBBBBBBB....BB.B..BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
            "BBBBBB.....B.....B.B...B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BB..B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.B.BBB.BBBBBBB",
            "BBBBBBBBBBBB....BB.B..BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BB.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
        )
        val session = LiftActivityLedger.SessionBounds("s", "d", 100, 300)
        val set = LiftActivityLedger.SetBounds("set", "s", "d", 110, 220)
        val actual = LiftActivityInterval.Kind.entries.map { kind ->
            buildString {
                for (start in 90..310 step 10) for (end in listOf(null, 110L, 120L, 220L, 300L, 310L)) {
                    val phase = LiftActivityInterval("00000000-0000-0000-0000-000000000001", kind, "set", start.toLong(), end)
                    try { LiftActivityLedger.validate(listOf(phase), session, listOf(set)); append('.') }
                    catch (error: LiftActivityLedger.ValidationException) { append(if (error.reason == LiftActivityLedger.Invalid.bounds) 'B' else 'X') }
                }
            }
        }
        assertEquals(expected, actual)
    }
}
