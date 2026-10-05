import SwiftUI
import StrandDesign

/// Live observations belong to this requested session, never the Today snapshot.
struct HeartRateSessionSheet: View {
    let expectedDeviceId: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = TimedHeartRateSession()
    @StateObject private var collection = WhoopCollectionModel()
    @State private var startedAt = Date()
    @State private var endedAt: Date?
    @State private var lastBPM: Int?
    @AppStorage(PuffinExperiment.keepRealtimeForDataKey) private var continuousHrvEnabled = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = NoopMetrics.dashboardHeroNumber

    var body: some View {
        NavigationStack {
            ScreenScaffold(title: "Live heart rate") {
                if session.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in sessionCard(now: context.date) }
                } else {
                    sessionCard(now: endedAt ?? Date())
                }
                if continuousHrvEnabled {
                    Text("Continuous HRV capture is enabled in Settings and may continue after this session.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                Text("This short session is separate from history sync. Receipt and storage evidence do not establish physiological accuracy.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { start() }
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.stop() } }
        .onChange(of: repo.deviceId) { _, _ in session.stop() }
        .onChange(of: live.connected) { _, _ in rearm() }
        .onChange(of: live.connectedWhoopDeviceId) { _, _ in rearm() }
        .onChange(of: live.activeIsWhoop) { _, _ in rearm() }
        .onChange(of: live.bonded) { _, _ in rearm() }
        .onChange(of: live.historyReady) { _, _ in rearm() }
        .onChange(of: session.isActive) { _, active in
            if !active {
                let now = Date()
                lastBPM = live.heartRateEvidence.sourceDeviceId == expectedDeviceId
                    ? live.heartRateEvidence.samples.last { $0.receivedAt >= startedAt.timeIntervalSince1970 && $0.receivedAt <= now.timeIntervalSince1970 }?.bpm : nil
                endedAt = now
            }
        }
        .task(id: "\(session.sessionId?.uuidString ?? "idle")|\(scenePhase)") {
            guard scenePhase == .active else { return }
            repeat {
                await collection.refresh(repo: repo, live: live)
                guard session.isActive else { return }
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            } while !Task.isCancelled
        }
    }

    private func status(_ now: Date) -> LiveHeartRateStatus {
        live.heartRateEvidence.status(connected: live.connected, isWhoop: live.activeIsWhoop,
            heartRate: live.heartRate, at: now.timeIntervalSince1970, silenceSeconds: LiveState.heartRateSilenceSeconds,
            expectedDeviceId: expectedDeviceId, connectionDeviceId: live.connectedWhoopDeviceId)
    }

    private func start() {
        guard scenePhase == .active, repo.deviceId == expectedDeviceId, status(Date()).connected else { return }
        startedAt = Date(); endedAt = nil; lastBPM = nil
        let owner = model
        session.start(deviceId: expectedDeviceId, request: { owner.startRealtimeHR() }, release: { owner.stopRealtimeHR() })
    }

    private func rearm() {
        guard scenePhase == .active, repo.deviceId == expectedDeviceId else { session.stop(); return }
        session.rearmIfValid(deviceId: expectedDeviceId, connected: status(Date()).connected,
                             isWhoop: live.activeIsWhoop, rearm: { model.rearmRealtimeIfWanted() })
    }

    private func sessionCard(now: Date) -> some View {
        let current = status(now)
        let belongsToSession = (live.heartRateEvidence.lastReceivedAt ?? 0) >= startedAt.timeIntervalSince1970
        let bpm = session.isActive ? (belongsToSession ? current.bpm : nil) : lastBPM
        let points = live.heartRateEvidence.sourceDeviceId == expectedDeviceId
            ? HeartDashboardProjection.trace(live.heartRateEvidence.samples.map {
                DashboardTraceSample(time: $0.receivedAt, value: Double($0.bpm))
            }, from: startedAt.timeIntervalSince1970, through: now.timeIntervalSince1970, gapSeconds: 1.5)
                .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) }
            : []
        return NoopCard(tint: StrandPalette.liquidHeart) {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text(session.isActive ? "\(session.remainingSeconds()) seconds remaining" : endedAt != nil ? "Session ended" : "Connect your WHOOP to start")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textSecondary)
                Text(bpm.map { "\($0) bpm" } ?? "— bpm").font(StrandFont.number(heroSize, weight: .bold))
                    .foregroundStyle(StrandPalette.liquidHeart)
                Text(session.isActive ? (bpm != nil ? "Fresh readable HR" : "Waiting for a fresh readable sample") : "Last readable value from this session")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                if !points.isEmpty {
                    DashboardChart(points: points, domain: startedAt...max(startedAt.addingTimeInterval(1), now),
                        range: max(0, (points.map(\.value).min() ?? 0) - 5)...((points.map(\.value).max() ?? 1) + 5),
                        tint: StrandPalette.liquidHeart, height: NoopMetrics.dashboardTraceHeight,
                        label: "Actual readable HR receipts during this session; missing readings remain gaps")
                } else {
                    Text("No readable samples captured yet").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: NoopMetrics.dashboardTraceHeight)
                }
                Button(session.isActive ? "Stop" : "Start 60-second session") {
                    if session.isActive { session.stop() } else { start() }
                }
                .buttonStyle(.bordered).tint(StrandPalette.liquidHeart).frame(minHeight: NoopMetrics.minimumTouchTarget)
                .disabled(!session.isActive && !current.connected)
                if let stored = collection.snapshot, stored.deviceId == expectedDeviceId {
                    Text("\(stored.heartRate.count.formatted()) measured HR samples stored today")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
}

/// Storage checks refresh only while the user is inspecting this detail.
struct DashboardCollectionSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var collection = WhoopCollectionModel()
    var body: some View {
        WhoopCollectionCard(collection: collection)
            .task(id: "\(repo.deviceId)|\(scenePhase)") {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await collection.refresh(repo: repo, live: live)
                    try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                }
            }
    }
}
