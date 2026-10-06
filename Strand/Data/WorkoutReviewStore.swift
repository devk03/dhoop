import Foundation

// iOS Cardio review metadata for this personal fork. It is device-local, is not part of the
// .noopbak contract, and changes neither the cross-platform detector nor the workout DB schema.
struct WorkoutReview: Codable, Equatable, Identifiable {
    enum Decision: String, Codable { case pending, workout, notWorkout }
    let id: String
    let deviceID: String
    var startSec: Int
    var endSec: Int
    var avgBpm: Int
    var peakBpm: Int
    var durationMin: Int
    var decision: Decision
    var linkedWorkout: Link?
    var recordingRemoved = false
    var lastOperationID: String?

    // Workout rows have a natural key, not a UUID. Retain its owner, exact bounds and source so
    // a later label change can never sweep overlapping manual/imported sessions.
    struct Link: Codable, Equatable {
        let owner: String
        let startSec: Int
        let endSec: Int
        let sport: String
        let source: String
        var sqliteRowID: Int64? = nil
    }

    init(deviceID: String, startSec: Int, endSec: Int, avgBpm: Int, peakBpm: Int,
         durationMin: Int, decision: Decision = .pending) {
        self.id = UUID().uuidString
        self.deviceID = deviceID
        self.startSec = startSec
        self.endSec = endSec
        self.avgBpm = avgBpm
        self.peakBpm = peakBpm
        self.durationMin = durationMin
        self.decision = decision
    }

    func overlaps(start: Int, end: Int) -> Bool { startSec < end && start < endSec }
}

struct WorkoutReviewStore {
    static let key = "cardio.workoutReviews.v1"
    var defaults: UserDefaults = .standard

    func all() throws -> [WorkoutReview] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return try JSONDecoder().decode([WorkoutReview].self, from: data)
    }

    func reviews(deviceID: String) throws -> [WorkoutReview] {
        try all().filter { $0.deviceID == deviceID }.sorted { $0.startSec > $1.startSec }
    }

    func save(_ review: WorkoutReview) throws {
        var items = try all()
        if let index = items.firstIndex(where: { $0.id == review.id && $0.deviceID == review.deviceID }) {
            items[index] = review
        } else {
            items.append(review)
        }
        defaults.set(try JSONEncoder().encode(items), forKey: Self.key)
    }

    // Pending snapshots can grow as the next sync completes a bout. A decision freezes its
    // evidence; no age pruning removes that record when the 48-hour detector scan expires.
    func capture(_ review: WorkoutReview) throws {
        if var existing = try reviews(deviceID: review.deviceID).first(where: {
            $0.overlaps(start: review.startSec, end: review.endSec)
        }) {
            guard existing.decision == .pending, existing.linkedWorkout == nil else { return }
            // A rolling window may truncate old evidence; only extend a pending snapshot.
            guard review.startSec <= existing.startSec, review.endSec >= existing.endSec else { return }
            existing.startSec = review.startSec; existing.endSec = review.endSec
            existing.avgBpm = review.avgBpm; existing.peakBpm = review.peakBpm
            existing.durationMin = review.durationMin
            try save(existing)
        } else { try save(review) }
    }
}

enum WorkoutReviewError: LocalizedError {
    case unavailable, busy, alreadySaved, changedRecording
    var errorDescription: String? {
        switch self {
        case .unavailable: return "This suggestion is no longer available for the selected device."
        case .busy: return "Another review is being saved. Try again."
        case .alreadySaved: return "A saved activity already overlaps this suggestion. Review it in Cardio history."
        case .changedRecording: return "The saved activity has changed. Review it in Cardio history before changing this label."
        }
    }
}

// Refresh can arrive in bursts after a backfill. Limit retention scans independently of UI visits.
struct WorkoutReviewCaptureCadence {
    private var lastAttempt: [String: Date] = [:]
    private var inFlight = false

    mutating func begin(deviceID: String, now: Date) -> Bool {
        guard !inFlight, lastAttempt[deviceID].map({ now.timeIntervalSince($0) >= 15 * 60 }) ?? true else { return false }
        inFlight = true
        lastAttempt[deviceID] = now
        return true
    }

    mutating func finish() { inFlight = false }
}

// One atomically replaced journal per reviewed suggestion bridges UserDefaults and SQLite. A
// completed journal remains available if the process exits before buffered preferences reach disk.
struct WorkoutReviewOperation: Codable, Equatable {
    let id: String
    let before: WorkoutReview
    let decision: WorkoutReview.Decision
    let link: WorkoutReview.Link?
    var completedReview: WorkoutReview?

    init(before: WorkoutReview, decision: WorkoutReview.Decision, link: WorkoutReview.Link?) {
        id = UUID().uuidString
        self.before = before
        self.decision = decision
        self.link = link
    }

    var receiptPrefix: String { "cardio.review.operation.\(before.id)." }
    var receiptKey: String { receiptPrefix + id }
}

struct WorkoutReviewOperationJournal {
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WorkoutReviewOperations", isDirectory: true)) {
        self.directory = directory
    }

    func save(_ operation: WorkoutReviewOperation) throws {
        guard UUID(uuidString: operation.before.id) != nil, UUID(uuidString: operation.id) != nil
        else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(operation).write(to: directory.appendingPathComponent(operation.before.id + ".json"), options: .atomic)
    }

    func operations(deviceID: String) throws -> [WorkoutReviewOperation] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(WorkoutReviewOperation.self, from: Data(contentsOf: $0)) }
            .filter { $0.before.deviceID == deviceID }
    }
}
