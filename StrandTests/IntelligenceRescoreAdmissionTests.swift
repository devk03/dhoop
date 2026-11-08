import XCTest
import Combine
import WhoopStore
@testable import Strand

@MainActor
final class IntelligenceRescoreAdmissionTests: XCTestCase {
    func testBusyStateAndAdmissionCoverTheInitialStorageWait() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "my-whoop")

        // Hold the real database queue so the first fingerprint cannot finish. The second idle
        // request must return while storage is held, rather than entering another scoring pass.
        let release = DispatchSemaphore(value: 0)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                try? store.registryWriter.write { _ in
                    continuation.resume()
                    _ = release.wait(timeout: .now() + 10)
                }
            }
        }
        defer { release.signal() }
        let busy = expectation(description: "Scoring reports busy while awaiting storage")
        let observation = engine.$computing.filter { $0 }.prefix(1).sink { _ in busy.fulfill() }
        defer { observation.cancel() }
        let first = Task { await engine.analyzeRecent(maxDays: 1, force: false) }
        await fulfillment(of: [busy], timeout: 2)
        XCTAssertTrue(engine.computing)

        let idleReturned = expectation(description: "Concurrent idle request is coalesced")
        let second = Task {
            await engine.analyzeRecent(maxDays: 1, force: false)
            idleReturned.fulfill()
        }
        await fulfillment(of: [idleReturned], timeout: 2)
        release.signal()
        await first.value
        await second.value
        XCTAssertFalse(engine.computing, "The claim must also release when there is no HR to score")
    }
}
