import Foundation

enum HIITWorkoutKind: String, Codable { case hiit, intervals
    var title: String { self == .hiit ? "HIIT" : "Intervals" }
}

struct HIITPlan: Codable, Equatable {
    var rounds = 8
    var workSeconds = 30
    var restSeconds = 60
    var warmupSeconds = 120
    var cooldownSeconds = 120
    var isValid: Bool {
        (1...30).contains(rounds) && (5...600).contains(workSeconds) && (5...600).contains(restSeconds)
            && (0...900).contains(warmupSeconds) && (0...900).contains(cooldownSeconds) && totalSeconds <= 10800
    }
    var totalSeconds: Int { warmupSeconds + rounds * workSeconds + max(0, rounds - 1) * restSeconds + cooldownSeconds }
    var intervals: [HIITInterval] {
        var result: [HIITInterval] = []
        var offset = 0
        func append(_ kind: HIITInterval.Kind, _ seconds: Int, _ round: Int) {
            guard seconds > 0 else { return }
            result.append(HIITInterval(index: result.count, kind: kind, round: round, start: offset, duration: seconds))
            offset += seconds
        }
        append(.warmup, warmupSeconds, 0)
        for round in 1...max(1, rounds) {
            append(.work, workSeconds, round)
            if round < rounds { append(.recovery, restSeconds, round) }
        }
        append(.cooldown, cooldownSeconds, 0)
        return result
    }
}

struct HIITInterval: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case warmup, work, recovery, cooldown
        var label: String {
            switch self { case .warmup: "Warm-up"; case .work: "Work"; case .recovery: "Recovery"; case .cooldown: "Cool-down" }
        }
    }
    let index: Int
    let kind: Kind
    let round: Int
    let start: Int
    let duration: Int
    var id: Int { index }
    var end: Int { start + duration }
    var label: String { round > 0 ? "\(kind.label) · round \(round)" : kind.label }
}

struct HIITHRPoint: Codable, Equatable, Identifiable {
    let elapsed: Double
    let receivedAt: Double
    let bpm: Int
    let interval: Int
    let segment: Int
    var id: Double { receivedAt }
}

struct HIITEffort {
    var observedSeconds: Double = 0
    var weightedBPM: Double = 0
    var peak: Int?
    var sampleCount = 0
    var zoneSeconds: [Double]
    var average: Double? { observedSeconds > 0 ? weightedBPM / observedSeconds : nil }
}

/// An explicit local workout log; missing observations never count as measured effort.
struct HIITSession: Codable, Equatable, Identifiable {
    enum State: String, Codable { case running, paused, completed, ended }
    let id: UUID
    let deviceId: String
    let plan: HIITPlan
    let zones: [RunningZoneTarget]
    let startedAt: Date
    var kind: HIITWorkoutKind?
    private(set) var state: State = .running
    private(set) var elapsed: Double = 0
    private(set) var points: [HIITHRPoint] = []
    private(set) var endedAt: Date?
    private var segment = 0
    private var continuity = false
    init?(deviceId: String, plan: HIITPlan, zones: [RunningZoneTarget], startedAt: Date = Date(), kind: HIITWorkoutKind = .hiit) {
        guard !deviceId.isEmpty, plan.isValid else { return nil }
        id = UUID(); self.deviceId = deviceId; self.plan = plan; self.zones = zones; self.startedAt = startedAt; self.kind = kind
    }
    var interval: HIITInterval? { plan.intervals.first { elapsed >= Double($0.start) && elapsed < Double($0.end) } }
    var remaining: Int { interval.map { max(0, Int(ceil(Double($0.end) - elapsed))) } ?? 0 }
    mutating func advance(to time: Double) -> Bool {
        guard state == .running, time.isFinite, time >= elapsed else { return false }
        let old = interval?.index
        elapsed = min(Double(plan.totalSeconds), time)
        if elapsed >= Double(plan.totalSeconds) { state = .completed }
        return old != interval?.index
    }
    mutating func breakContinuity() { if continuity { segment += 1 }; continuity = false }
    mutating func pause() { if state == .running { state = .paused }; breakContinuity() }
    mutating func resume() { if state == .paused { state = .running }; breakContinuity() }
    mutating func finish(at date: Date = Date()) { if state != .completed { state = .ended }; endedAt = date; breakContinuity() }
    @discardableResult mutating func observe(_ sample: RunningHeartRateSample, elapsed sampleElapsed: Double, now: Double) -> Bool {
        guard (state == .running || state == .completed), endedAt == nil, sample.deviceId == deviceId, (30...220).contains(sample.bpm),
              sample.receivedAt.isFinite, now.isFinite, sampleElapsed.isFinite,
              sample.receivedAt >= startedAt.timeIntervalSince1970, now >= sample.receivedAt,
              now - sample.receivedAt <= RunningZoneSession.maximumGap, sampleElapsed >= 0,
              sampleElapsed <= elapsed,
              let phase = plan.intervals.first(where: { sampleElapsed >= Double($0.start) && sampleElapsed < Double($0.end) }) else {
            breakContinuity(); return false
        }
        if let last = points.last {
            guard sample.receivedAt > last.receivedAt, sampleElapsed > last.elapsed else { return false }
            if sample.receivedAt - last.receivedAt > RunningZoneSession.maximumGap || sampleElapsed - last.elapsed > RunningZoneSession.maximumGap { breakContinuity() }
        }
        points.append(HIITHRPoint(elapsed: sampleElapsed, receivedAt: sample.receivedAt, bpm: sample.bpm, interval: phase.index, segment: segment))
        continuity = true
        return true
    }
    func effort(interval index: Int? = nil) -> HIITEffort {
        let selected = points.filter { index == nil || $0.interval == index }
        var result = HIITEffort(peak: selected.map(\.bpm).max(), sampleCount: selected.count, zoneSeconds: Array(repeating: 0, count: zones.count))
        for (a, b) in zip(points, points.dropFirst()) {
            let dt = b.elapsed - a.elapsed
            guard a.segment == b.segment, dt > 0, dt <= RunningZoneSession.maximumGap else { continue }
            if let index, a.interval != index || b.interval != index { continue }
            result.observedSeconds += dt
            result.weightedBPM += Double(a.bpm + b.bpm) / 2 * dt
            for i in zones.indices where zones[i].contains(a.bpm) && zones[i].contains(b.bpm) { result.zoneSeconds[i] += dt }
        }
        return result
    }
}
