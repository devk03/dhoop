import Foundation

public struct ReadableHeartRateSample: Equatable, Sendable {
    public let receivedAt: TimeInterval
    public let bpm: Int
}

/// One resolution of connection and readable receipt; every surface uses the same freshness gate.
public struct LiveHeartRateStatus: Equatable {
    public let bpm: Int?
    public let sampleAge: TimeInterval?
    public let packets: Int
    public let connected: Bool
    public let isWhoop: Bool
    public var isReceiving: Bool { bpm != nil }
}

/// Receipt evidence counts readable packets, including unchanged BPM, rather than UI value changes.
public struct LiveHeartRateEvidence: Equatable {
    public private(set) var sourceDeviceId: String?
    public private(set) var packets = 0
    public private(set) var lastReceivedAt: TimeInterval?
    public private(set) var samples: [ReadableHeartRateSample] = []
    public static let chartWindowSeconds: TimeInterval = 300
    public static let sampleCapacity = 600

    public init() {}

    public mutating func record(bpm: Int? = nil, deviceId: String? = nil, at time: TimeInterval = Date().timeIntervalSince1970) {
        guard time.isFinite else { return }
        if let deviceId, let previous = sourceDeviceId, previous != deviceId { self = LiveHeartRateEvidence() }
        sourceDeviceId = deviceId
        packets += 1
        lastReceivedAt = time
        if let bpm, (30...220).contains(bpm) {
            // One actual receipt per second; repeated BPM still advances the trace. No timer-made points.
            if let last = samples.last, Int(last.receivedAt) == Int(time) {
                samples[samples.count - 1] = ReadableHeartRateSample(receivedAt: time, bpm: bpm)
            } else {
                samples.append(ReadableHeartRateSample(receivedAt: time, bpm: bpm))
            }
            samples.removeAll { $0.receivedAt < time - Self.chartWindowSeconds || $0.receivedAt > time }
            if samples.count > Self.sampleCapacity { samples.removeFirst(samples.count - Self.sampleCapacity) }
        }
    }

    public func isFresh(at time: TimeInterval, silenceSeconds: TimeInterval) -> Bool {
        guard let lastReceivedAt else { return false }
        let age = time - lastReceivedAt
        return age >= 0 && age < silenceSeconds
    }

    public func status(connected: Bool, isWhoop: Bool, heartRate: Int?, at time: TimeInterval,
                       silenceSeconds: TimeInterval, expectedDeviceId: String? = nil, connectionDeviceId: String? = nil) -> LiveHeartRateStatus {
        let attributable = isWhoop && (expectedDeviceId == nil || sourceDeviceId == expectedDeviceId)
        let age = attributable ? lastReceivedAt.flatMap { time >= $0 ? time - $0 : nil } : nil
        let linked = connected && isWhoop && (expectedDeviceId == nil || connectionDeviceId == expectedDeviceId)
        let readable = linked && attributable && (heartRate ?? 0) > 0 && isFresh(at: time, silenceSeconds: silenceSeconds)
        return LiveHeartRateStatus(bpm: readable ? heartRate : nil, sampleAge: age, packets: attributable ? packets : 0,
                                   connected: linked, isWhoop: isWhoop)
    }
}
