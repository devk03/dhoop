package com.noop.protocol

/** Revision-4 candidate facts. Zero time is ambiguous, never proof of an available slot. */
class Whoop5AlarmRecord private constructor(val bytes: List<Int>) {
    val slot: Int get() = bytes[1]
    val epoch: Long get() = (0..3).fold(0L) { v, i -> v or (bytes[2 + i].toLong() shl (i * 8)) }
    val isZeroTime: Boolean get() = epoch == 0L
    val isClearedCandidate: Boolean get() = bytes.drop(2).all { it == 0 }
    companion object {
        fun decode(payload: List<Int>, slot: Int): Whoop5AlarmRecord? {
            if (slot !in 1..6 || payload.size !in 21..24 || payload.any { it !in 0..255 }
                || payload[0] != 4 || payload[1] != slot || payload.drop(21).any { it != 0 }) return null
            val body = payload.take(21)
            val ticks = body[6] or (body[7] shl 8)
            if (ticks >= 32768 || body.subList(8, 16).any { it > 251 } || body[18] >= 8
                || body[20] > 1 || (body[18] == 7 && body[19] !in 30..120)) return null
            return Whoop5AlarmRecord(body)
        }
        fun standard(slot: Int, epoch: Long): Whoop5AlarmRecord? {
            if (slot !in 1..6 || epoch !in 1L..4294967295L) return null
            return decode(AlarmPayload.build(epoch * 1000, slot).map { it.toInt() and 255 } + 0, slot)
        }
        fun clearPayload(slot: Int): List<Int>? = if (slot in 1..6) listOf(2, slot) else null
    }
}
