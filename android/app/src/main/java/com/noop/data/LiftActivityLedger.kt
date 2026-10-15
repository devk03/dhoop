package com.noop.data

/** Source timing twin of Swift LiftActivityLedger. No Android session UI writes these phases yet. */
data class LiftActivityInterval(
    val sourceIntervalId: String,
    val kind: Kind,
    val sourceSetId: String?,
    val startedAt: Long,
    val endedAt: Long?,
) {
    enum class Kind { work, rest, pause }
}

object LiftActivityLedger {
    enum class Invalid { malformed, bounds, reference, overlap }
    class ValidationException(val reason: Invalid) : IllegalArgumentException(reason.name)
    data class SessionBounds(val id: String, val deviceId: String, val startTs: Long, val endTs: Long?)
    data class SetBounds(val id: String, val sessionId: String, val deviceId: String, val startTs: Long?, val endTs: Long?)
    const val maximumIntervals = 512
    private val uuid = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
    private fun reject(reason: Invalid): Nothing = throw ValidationException(reason)

    fun validate(intervals: List<LiftActivityInterval>, session: SessionBounds, sets: List<SetBounds>, retainedSetIDs: Set<String> = emptySet()) {
        if (intervals.size > maximumIntervals || intervals.map { it.sourceIntervalId }.toSet().size != intervals.size ||
            intervals.any { !uuid.matches(it.sourceIntervalId) }) reject(Invalid.malformed)
        val known = sets.groupBy { it.id }.mapValues { it.value.first() }
        for (interval in intervals) {
            if (interval.startedAt < session.startTs || (session.endTs != null && interval.startedAt > session.endTs) ||
                (interval.endedAt != null && (interval.endedAt < interval.startedAt || (session.endTs != null && interval.endedAt > session.endTs)))) reject(Invalid.bounds)
            if (interval.kind == LiftActivityInterval.Kind.work && interval.sourceSetId == null) reject(Invalid.reference)
            if (interval.sourceSetId != null) {
                val set = known[interval.sourceSetId]
                if (set == null) {
                    if (retainedSetIDs.contains(interval.sourceSetId)) continue
                    reject(Invalid.reference)
                }
                if (set.sessionId != session.id || set.deviceId != session.deviceId) reject(Invalid.reference)
                if (interval.kind != LiftActivityInterval.Kind.rest) {
                    if ((set.startTs != null && interval.startedAt < set.startTs) ||
                        (set.endTs != null && interval.startedAt > set.endTs) ||
                        (interval.endedAt != null && set.endTs != null && interval.endedAt > set.endTs)) reject(Invalid.bounds)
                }
            }
        }
        val closed = intervals.filter { (it.endedAt ?: it.startedAt) > it.startedAt }.sortedBy { it.startedAt }
        for ((left, right) in closed.zipWithNext()) if (left.endedAt!! > right.startedAt) reject(Invalid.overlap)
    }

    /** Half-open windows; unknown ends remain unknown. Call validate before aggregating. */
    fun workWindows(intervals: List<LiftActivityInterval>, setID: String): List<Pair<Long, Long>> = intervals.mapNotNull {
        if (it.kind != LiftActivityInterval.Kind.work || it.sourceSetId != setID || it.endedAt == null || it.endedAt <= it.startedAt) null
        else Pair(it.startedAt, it.endedAt)
    }.sortedBy { it.first }
}
