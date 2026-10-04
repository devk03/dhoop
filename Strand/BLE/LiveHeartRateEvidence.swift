import Foundation

/// Receipt evidence counts readable packets, including unchanged BPM, rather than UI value changes.
public struct LiveHeartRateEvidence: Equatable {
    public private(set) var packets = 0
    public private(set) var lastReceivedAt: TimeInterval?

    public init() {}

    public mutating func record(at time: TimeInterval = Date().timeIntervalSince1970) {
        packets += 1
        lastReceivedAt = time
    }

    public func isFresh(at time: TimeInterval, silenceSeconds: TimeInterval) -> Bool {
        guard let lastReceivedAt else { return false }
        let age = time - lastReceivedAt
        return age >= 0 && age < silenceSeconds
    }
}
