package com.noop.analytics

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

data class AlarmScheduleRule(val minute: Int, val weekdays: Set<Int> = emptySet(),
    val oneTimeEpoch: Long? = null, val skippedEpochs: Set<Long> = emptySet(), val timeZoneID: String? = null)

/** Pure twin of Swift's finite dated schedule. Empty weekdays means one-time. */
object AlarmOccurrencePlanner {
    fun dates(rule: AlarmScheduleRule, after: Long, zone: ZoneId, limit: Int = 6): List<Long> {
        if (rule.minute !in 0..1439 || rule.weekdays.any { it !in 1..7 } || limit <= 0
            || rule.oneTimeEpoch?.let { it <= 0 } == true || rule.skippedEpochs.any { it <= 0 }) return emptyList()
        val resolvedZone = try { rule.timeZoneID?.let { ZoneId.of(it) } ?: zone } catch (_: Exception) { return emptyList() }
        if (rule.weekdays.isEmpty()) return rule.oneTimeEpoch?.let {
            if (it > after && it !in rule.skippedEpochs) listOf(it) else emptyList()
        } ?: emptyList()
        val start = Instant.ofEpochSecond(after).atZone(resolvedZone).toLocalDate()
        val result = mutableListOf<Long>()
        for (offset in 0L..63L) {
            val day = start.plusDays(offset)
            val weekday = day.dayOfWeek.value % 7 + 1
            if (weekday !in rule.weekdays) continue
            val local = day.atTime(LocalTime.of(rule.minute / 60, rule.minute % 60))
            val offsets = resolvedZone.rules.getValidOffsets(local)
            // A nonexistent wall time moves to the first valid instant, not the gap duration later.
            val due = if (offsets.isEmpty()) resolvedZone.rules.getTransition(local).dateTimeAfter.atZone(resolvedZone)
                else local.atZone(resolvedZone).withEarlierOffsetAtOverlap()
            val epoch = due.toEpochSecond()
            if (epoch > after && epoch !in rule.skippedEpochs) result.add(epoch)
            if (result.size == minOf(limit, 6)) break
        }
        return result
    }
}
