package com.noop.analytics

/** Analysis-only repair of a missing wrist-on event. Mirrors Swift SleepWearEvidence. */
object SleepWearEvidence {
    fun confirmedWearStart(samples: List<Pair<Long, Int>>, after: Long, through: Long): Long? {
        val validBySecond = HashMap<Long, Boolean>()
        for ((ts, bpm) in samples) {
            if (ts <= after || ts > through) continue
            validBySecond[ts] = (validBySecond[ts] ?: true) && bpm in 30..220
        }
        val seconds = ArrayList<Long>()
        var first = 0
        for (ts in validBySecond.keys.sorted()) {
            if (validBySecond[ts] != true) { seconds.clear(); first = 0; continue }
            if (seconds.isNotEmpty() && ts - seconds.last() > 5) { seconds.clear(); first = 0 }
            seconds.add(ts)
            while (first + 1 < seconds.size && seconds[first + 1] <= ts - 60) first++
            val span = ts - seconds[first]
            if (span >= 60 && (seconds.size - first) * 5L >= (span + 1) * 4) return seconds[first]
        }
        return null
    }
}
