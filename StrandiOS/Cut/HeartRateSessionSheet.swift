import SwiftUI
import StrandDesign

/// This leaf owns the only per-packet UI updates inside the otherwise static HR card.
struct InlineHeartRateCapture: View {
    let expectedDeviceId: String
    let enabled: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = TimedHeartRateSession()
    @StateObject private var collection = WhoopCollectionModel()
    @State private var startedAt = Date()
    @State private var endedAt: Date?
    @State private var lastBPM: Int?
    @ScaledMetric(relativeTo: .title) private var numberSize = NoopMetrics.dashboardMetricNumber

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if session.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in capture(now: context.date) }
            } else {
                Button { start() } label: { Label("Live HR · 60s", systemImage: "waveform.path.ecg") }
                    .font(StrandFont.subhead).buttonStyle(.bordered).tint(StrandPalette.liquidHeart)
                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                    .disabled(!enabled || !status(Date()).connected)
                    .accessibilityHint("Collects live heart rate here for sixty seconds")
                if let endedAt {
                    Text("Session ended · \(lastBPM.map { "\($0) bpm" } ?? "no readable sample") · \(endedAt.formatted(.dateTime.hour().minute()))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
        .onDisappear { session.stop() }
        .onChange(of: enabled) { _, value in if !value { session.stop() } }
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
            guard session.isActive, scenePhase == .active,
                  ProcessInfo.processInfo.arguments.contains("--collection-proof") else { return }
            repeat {
                await collection.refresh(repo: repo, live: live)
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            } while session.isActive && !Task.isCancelled
        }
    }

    private func status(_ now: Date) -> LiveHeartRateStatus {
        live.heartRateEvidence.status(connected: live.connected, isWhoop: live.activeIsWhoop,
            heartRate: live.heartRate, at: now.timeIntervalSince1970, silenceSeconds: LiveState.heartRateSilenceSeconds,
            expectedDeviceId: expectedDeviceId, connectionDeviceId: live.connectedWhoopDeviceId)
    }
    private func start() {
        guard enabled, scenePhase == .active, repo.deviceId == expectedDeviceId, status(Date()).connected else { return }
        startedAt = Date(); endedAt = nil; lastBPM = nil
        let owner = model
        session.start(deviceId: expectedDeviceId, request: { owner.startRealtimeHR() }, release: { owner.stopRealtimeHR() })
    }
    private func rearm() {
        guard enabled, scenePhase == .active, repo.deviceId == expectedDeviceId else { session.stop(); return }
        session.rearmIfValid(deviceId: expectedDeviceId, connected: status(Date()).connected,
                             isWhoop: live.activeIsWhoop, rearm: { model.rearmRealtimeIfWanted() })
    }
    private func capture(now: Date) -> some View {
        let current = status(now)
        let belongs = (live.heartRateEvidence.lastReceivedAt ?? 0) >= startedAt.timeIntervalSince1970
        let bpm = belongs ? current.bpm : nil
        let points = live.heartRateEvidence.sourceDeviceId == expectedDeviceId
            ? HeartDashboardProjection.trace(live.heartRateEvidence.samples.map {
                DashboardTraceSample(time: $0.receivedAt, value: Double($0.bpm))
            }, from: startedAt.timeIntervalSince1970, through: now.timeIntervalSince1970, gapSeconds: 1.5)
                .map { TrendPoint(date: Date(timeIntervalSince1970: $0.time), value: $0.value, segment: $0.segment) } : []
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Live · \(session.remainingSeconds()) seconds remaining").font(StrandFont.subhead).foregroundStyle(StrandPalette.liquidHeart)
            Text(bpm.map { "\($0) bpm" } ?? "— bpm").font(StrandFont.number(numberSize, weight: .bold))
            Text(bpm != nil ? "Fresh readable HR" : "Waiting for a fresh reading").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            if !points.isEmpty {
                DashboardChart(points: points, domain: startedAt...max(startedAt.addingTimeInterval(1), now),
                    range: max(0, (points.map(\.value).min() ?? 0) - 5)...((points.map(\.value).max() ?? 1) + 5),
                    tint: StrandPalette.liquidHeart, height: NoopMetrics.dashboardTrendHeight,
                    label: "Actual HR during this requested session; missing readings remain gaps", compact: true, valueFormat: { "\(Int($0)) bpm · WHOOP" })
            }
            Button("Stop live HR") { session.stop() }.font(StrandFont.subhead)
                .buttonStyle(.bordered).tint(StrandPalette.liquidHeart).frame(minHeight: NoopMetrics.minimumTouchTarget)
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
