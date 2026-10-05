import SwiftUI
import StrandDesign

/// Expanded collection evidence, reached from the compact status row on Today.
struct WhoopCollectionCard: View {
    @ObservedObject var collection: WhoopCollectionModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let status = live.heartRateEvidence.status(connected: live.connected, isWhoop: live.activeIsWhoop,
                    heartRate: live.heartRate, at: context.date.timeIntervalSince1970,
                    silenceSeconds: LiveState.heartRateSilenceSeconds, expectedDeviceId: repo.deviceId, connectionDeviceId: live.connectedWhoopDeviceId)
                ScreenScaffold(title: "Data collection") {
                    VStack(spacing: NoopMetrics.sectionGap) {
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                Text(collection.deviceName(for: repo.deviceId)).font(StrandFont.headline)
                                evidenceRow("Model", collection.identity.flatMap { $0.id == repo.deviceId ? $0.model : nil } ?? "Not resolved")
                                evidenceRow("Device identity", repo.deviceId)
                                evidenceRow("Radio connection", status.connected ? "Connected" : "Disconnected")
                                evidenceRow("Live HR", status.isReceiving ? "Receiving readable samples" : "No fresh readable sample")
                                evidenceRow("Last readable HR", (status.sampleAge != nil ? live.heartRateEvidence.lastReceivedAt.map(fullTime) : nil) ?? "None for this device")
                                evidenceRow("Sample age", status.sampleAge.map { "\(Int($0)) seconds" } ?? "Unavailable")
                                evidenceRow("Readable packets", "\(status.packets.formatted()) this connection")
                                if let battery = live.reportedBattery(for: repo.deviceId) {
                                    evidenceRow("Last reported battery", "\(Int(battery.rounded()))%")
                                }
                            }
                        }
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                Text("Stored on this phone").font(StrandFont.headline)
                                if let snapshot = collection.snapshot, snapshot.deviceId == repo.deviceId {
                                    evidenceRow("Window starts", fullTime(Double(snapshot.fromTs)))
                                    evidenceRow("Window ends", fullTime(Double(snapshot.toTs)))
                                    evidenceRow("Source", snapshot.deviceId)
                                    streamRow("Measured HR", count: snapshot.heartRate.count, latest: snapshot.heartRate.latestTs)
                                    streamRow("Stored R–R", count: snapshot.rr.count, latest: snapshot.rr.latestTs)
                                    streamRow("Usable R–R inputs", count: snapshot.scorableRR.count, latest: snapshot.scorableRR.latestTs)
                                    streamRow("Optical HR estimates", count: snapshot.opticalEstimates.count, latest: snapshot.opticalEstimates.latestTs)
                                    streamRow("Step records", count: snapshot.steps.count, latest: snapshot.steps.latestTs)
                                    if let added = collection.addedHR {
                                        Text(added >= 0 ? "\(added.formatted()) HR samples added since the preceding check." : "Stored count decreased since the preceding check.")
                                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                    }
                                    if let checked = collection.checkedAt { evidenceRow("Checked at", fullTime(checked.timeIntervalSince1970)) }
                                } else {
                                    Text("No storage observation available yet.").font(StrandFont.body)
                                }
                                Text("Usable R–R inputs pass the same source and timestamp rules as HRV reads. HRV still needs interval quality checks and suitable sleep coverage.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            }
                        }
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                                Text("History & checks").font(StrandFont.headline)
                                evidenceRow("History readiness", live.historyIsReady(for: repo.deviceId) ? "Ready" : "Not ready")
                                evidenceRow("Last successful sync", live.successfulSyncAt(for: repo.deviceId).map(fullTime) ?? "None recorded")
                                evidenceRow("Storage error", collection.error ?? "None reported")
                                evidenceRow("Sync error · source unverified", live.lastSyncError ?? "None reported")
                                Text("Connection, fresh receipt and stored samples are separate evidence. Collection checks do not establish the physiological accuracy of derived metrics.")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                                Button("Check now") { Task { await collection.refresh(repo: repo, live: live) } }
                                    .buttonStyle(.bordered).frame(minHeight: NoopMetrics.minimumTouchTarget)
                                ShareLink(item: collection.proofText(live: live, now: context.date, deviceId: repo.deviceId)) {
                                    Label("Share collection proof", systemImage: "square.and.arrow.up")
                                }
                                .frame(minHeight: NoopMetrics.minimumTouchTarget)
                                Button("Manage devices") { dismiss(); router.requestedDestination = .devices }
                                    .frame(minHeight: NoopMetrics.minimumTouchTarget)
                            }
                        }
                    }
                    .foregroundStyle(StrandPalette.textPrimary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func evidenceRow(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(name).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            Text(value).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func streamRow(_ name: String, count: Int, latest: Int?) -> some View {
        evidenceRow(name, "\(count.formatted()) · latest \(latest.map { fullTime(Double($0)) } ?? "none")")
    }

    private func fullTime(_ time: TimeInterval) -> String {
        Date(timeIntervalSince1970: time).formatted(.dateTime.month(.abbreviated).day().year().hour().minute().second())
    }
}
