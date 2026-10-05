import Foundation

/// Running uses observed intervals, not the historical analytics tail/hold convention.
struct RunningZoneTarget: Codable, Equatable {
    let name: String
    let lowerBPM: Int
    /// Exclusive; nil means no upper boundary (Zone 5).
    let upperBPM: Int?
    let method: String

    var isValid: Bool {
        (30...220).contains(lowerBPM) && (upperBPM == nil || (upperBPM! > lowerBPM && upperBPM! <= 251))
    }
    func contains(_ bpm: Int) -> Bool {
        bpm >= lowerBPM && (upperBPM == nil || bpm < upperBPM!)
    }
    var rangeLabel: String {
        upperBPM.map { "\(lowerBPM)–\($0 - 1) bpm" } ?? "\(lowerBPM)+ bpm"
    }

    /// Public HRR bands, evaluated locally. These are not WHOOP's personalized baselines.
    static func reserveZones(maxHR: Double, restingHR: Double, method: String) -> [Self] {
        guard maxHR.isFinite, restingHR.isFinite, maxHR > restingHR,
              (30...250).contains(maxHR), restingHR >= 30 else { return [] }
        let reserve = maxHR - restingHR
        let edges = [0.40, 0.60, 0.70, 0.80, 0.90]
        return edges.enumerated().map { index, fraction in
            Self(name: "Zone \(index + 1)", lowerBPM: Int(ceil(restingHR + reserve * fraction)),
                 upperBPM: index == 4 ? nil : Int(ceil(restingHR + reserve * edges[index + 1])), method: method)
        }.filter(\.isValid)
    }

    static func customZones(lowerBounds: [Double]) -> [Self] {
        guard lowerBounds.count == 5, lowerBounds.allSatisfy({ $0.isFinite && (30...250).contains($0) }),
              zip(lowerBounds, lowerBounds.dropFirst()).allSatisfy({ $0 < $1 }) else { return [] }
        let zones = lowerBounds.enumerated().map { index, bound in
            Self(name: "Zone \(index + 1)", lowerBPM: Int(ceil(bound)),
                 upperBPM: index == 4 ? nil : Int(ceil(lowerBounds[index + 1])), method: "Configured custom BPM zones")
        }
        return zones.allSatisfy(\.isValid) ? zones : []
    }
}

struct RunningHeartRateSample: Equatable {
    let deviceId: String
    let bpm: Int
    let receivedAt: TimeInterval
}

/// Only adjacent, fresh, same-device observations can advance progress or issue a zone cue.
struct RunningZoneSession: Codable, Equatable {
    enum Phase: String, Codable { case running, paused, completed, ended }
    enum Outside: String { case below, above }
    struct Observation: Equatable {
        let accepted: Bool
        let alert: Outside?
    }

    let id: UUID
    let deviceId: String
    let target: RunningZoneTarget
    let goalSeconds: TimeInterval
    let startedAt: Date
    private(set) var phase: Phase = .running
    private(set) var inZoneSeconds: TimeInterval = 0
    private(set) var observedSeconds: TimeInterval = 0
    private(set) var readableSamples = 0
    private(set) var weightedHeartRate: Double = 0
    private(set) var maximumBPM: Int?
    private(set) var latestBPM: Int?
    private(set) var lastAcceptedAt: TimeInterval?
    private var previous: CodableSample?
    private var hasEnteredZone = false
    private var outsideSince: TimeInterval?
    private var outsideDirection: String?
    private var lastAlertAt: TimeInterval?

    static let maximumGap: TimeInterval = 2
    static let outsideDwell: TimeInterval = 3
    static let alertCooldown: TimeInterval = 30

    private struct CodableSample: Codable, Equatable {
        let bpm: Int
        let time: TimeInterval
    }

    init?(deviceId: String, target: RunningZoneTarget, goalSeconds: TimeInterval, startedAt: Date = Date()) {
        guard !deviceId.isEmpty, target.isValid, goalSeconds.isFinite, goalSeconds > 0,
              startedAt.timeIntervalSince1970.isFinite else { return nil }
        self.id = UUID(); self.deviceId = deviceId; self.target = target
        self.goalSeconds = goalSeconds; self.startedAt = startedAt
    }

    var averageBPM: Double? { observedSeconds > 0 ? weightedHeartRate / observedSeconds : nil }
    var remainingSeconds: Int { Int(ceil(max(0, goalSeconds - inZoneSeconds))) }

    mutating func pause() {
        if phase == .running { phase = .paused }
        breakContinuity()
    }
    mutating func resume() {
        guard phase == .paused else { return }
        phase = .running
        breakContinuity()
    }
    mutating func end() {
        if phase != .completed { phase = .ended }
        breakContinuity()
    }
    mutating func breakContinuity() {
        previous = nil; outsideSince = nil; outsideDirection = nil; latestBPM = nil
    }

    /// Invalid/stale evidence never starts a dwell or manufactures time; duplicates are inert.
    mutating func observe(_ sample: RunningHeartRateSample, now: TimeInterval,
                          connected: Bool, alertsEnabled: Bool = true, mayBuzz: Bool = true) -> Observation {
        guard phase == .running else { return Observation(accepted: false, alert: nil) }
        guard connected, sample.deviceId == deviceId, (30...220).contains(sample.bpm),
              sample.receivedAt.isFinite, now.isFinite,
              sample.receivedAt >= startedAt.timeIntervalSince1970,
              now >= sample.receivedAt, now - sample.receivedAt <= Self.maximumGap else {
            breakContinuity()
            return Observation(accepted: false, alert: nil)
        }
        guard lastAcceptedAt == nil || sample.receivedAt > lastAcceptedAt! else {
            return Observation(accepted: false, alert: nil)
        }
        readableSamples += 1
        maximumBPM = max(maximumBPM ?? sample.bpm, sample.bpm)
        latestBPM = sample.bpm; lastAcceptedAt = sample.receivedAt
        let inside = target.contains(sample.bpm)
        let gap = previous.map { sample.receivedAt - $0.time }
        let contiguous = gap.map { $0 > 0 && $0 <= Self.maximumGap } ?? false
        if !contiguous { outsideSince = nil; outsideDirection = nil }
        if let previous, let gap, contiguous {
            observedSeconds += gap
            weightedHeartRate += (Double(previous.bpm) + Double(sample.bpm)) / 2 * gap
            // Boundary-crossing intervals are deliberately not credited to the goal.
            if inside && target.contains(previous.bpm) {
                inZoneSeconds = min(goalSeconds, inZoneSeconds + gap)
            }
        }
        previous = CodableSample(bpm: sample.bpm, time: sample.receivedAt)
        if inside {
            hasEnteredZone = true; outsideSince = nil; outsideDirection = nil
        }
        if inZoneSeconds >= goalSeconds {
            phase = .completed; previous = nil; outsideSince = nil
            return Observation(accepted: true, alert: nil)
        }
        var alert: Outside?
        if !inside && hasEnteredZone {
            let direction: Outside = sample.bpm < target.lowerBPM ? .below : .above
            if outsideDirection != direction.rawValue {
                outsideSince = sample.receivedAt; outsideDirection = direction.rawValue
            } else if outsideSince == nil { outsideSince = sample.receivedAt }
            if let since = outsideSince, sample.receivedAt - since >= Self.outsideDwell,
               alertsEnabled, mayBuzz,
               lastAlertAt.map({ sample.receivedAt - $0 >= Self.alertCooldown }) ?? true {
                alert = direction; lastAlertAt = sample.receivedAt
            }
        }
        return Observation(accepted: true, alert: alert)
    }
}

struct RunningSessionSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let deviceId: String
    let target: RunningZoneTarget
    let startedAt: Date
    let endedAt: Date
    let elapsedSeconds: TimeInterval
    let inZoneSeconds: TimeInterval
    let goalSeconds: TimeInterval
    let observedSeconds: TimeInterval
    let readableSamples: Int
    let averageBPM: Double?
    let maximumBPM: Int?
    let goalMet: Bool
}
