package com.noop.analytics

/** Analysis-only repair of a missing wrist-on event. Mirrors Swift SleepWearEvidence. */
object SleepWearEvidence {
    fun confirmedWearStart(samples: List<Pair<Long, Int>>, after: Long, through: Long): Long? {
        return confirmedWearStart(canonicalSamples(samples).filter { it.first > after && it.first <= through })
    }

    fun offWristIntervals(events: List<Pair<Long, Boolean>>, samples: List<Pair<Long, Int>>, through: Long): List<Pair<Long, Long>> {
        val eventBySecond = HashMap<Long, Boolean>()
        for ((ts, off) in events) if (ts <= through) eventBySecond[ts] = (eventBySecond[ts] ?: false) || off
        if (!eventBySecond.values.contains(true)) return emptyList()
        val readings = canonicalSamples(samples)
        var cursor = 0
        var offStart: Long? = null
        val result = ArrayList<Pair<Long, Long>>()
        fun close(start: Long, end: Long, includingEnd: Boolean = false) {
            if (end <= start) return
            while (cursor < readings.size && readings[cursor].first <= start) cursor++
            val first = cursor
            while (cursor < readings.size && (if (includingEnd) readings[cursor].first <= end else readings[cursor].first < end)) cursor++
            val resolvedEnd = confirmedWearStart(readings.subList(first, cursor)) ?: end
            val last = result.lastOrNull()
            if (last != null && last.second == start) result[result.lastIndex] = last.first to resolvedEnd
            else result.add(start to resolvedEnd)
        }
        for (ts in eventBySecond.keys.sorted()) {
            offStart?.let { close(it, ts) }
            offStart = if (eventBySecond[ts] == true) ts else null
        }
        offStart?.let { close(it, through, true) }
        return result
    }

    private fun canonicalSamples(samples: List<Pair<Long, Int>>): List<Pair<Long, Boolean>> {
        val validBySecond = HashMap<Long, Boolean>()
        for ((ts, bpm) in samples) {
            validBySecond[ts] = (validBySecond[ts] ?: true) && bpm in 30..220
        }
        return validBySecond.keys.sorted().map { it to validBySecond.getValue(it) }
    }

    private fun confirmedWearStart(ordered: List<Pair<Long, Boolean>>): Long? {
        val seconds = ArrayList<Long>()
        var first = 0
        for ((ts, valid) in ordered) {
            if (!valid) { seconds.clear(); first = 0; continue }
            if (seconds.isNotEmpty() && ts - seconds.last() > 5) { seconds.clear(); first = 0 }
            seconds.add(ts)
            while (first + 1 < seconds.size && seconds[first + 1] <= ts - 60) first++
            val span = ts - seconds[first]
            if (span >= 60 && (seconds.size - first) * 5L >= (span + 1) * 4) return seconds[first]
        }
        return null
    }
}
