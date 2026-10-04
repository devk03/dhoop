import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A focused heart dashboard using the same stored metrics and strain scorer as the upstream Today.
struct HeartMetricsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var live: LiveState
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @State private var strain: Double?
    @State private var strainCaption = "Needs more heart-rate data"
    @State private var hrv: ResolvedMetricPoint?
    @State private var steps: ResolvedMetricPoint?
    @State private var vo2: Double?
    @State private var vo2Caption = "No VO₂ max data yet"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fresh = live.connected && live.activeIsWhoop && (live.heartRate ?? 0) > 0 && live.heartRateEvidence.isFresh(
                at: context.date.timeIntervalSince1970, silenceSeconds: LiveState.heartRateSilenceSeconds)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.gap),
                                GridItem(.flexible(), spacing: NoopMetrics.gap)], spacing: NoopMetrics.gap) {
                metric("Heart rate", icon: "heart.fill", value: fresh ? live.heartRate.map(String.init) ?? "—" : "—",
                       unit: "bpm", caption: fresh ? "Live from WHOOP"
                       : live.connected ? "Waiting for fresh heart rate" : "WHOOP disconnected", tint: StrandPalette.liquidHeart)
                metric("Strain", icon: "flame.fill",
                       value: strain.map { UnitFormatter.effortDisplay($0, scale: UnitPrefs.resolveEffortScale(effortScaleRaw)) } ?? "—",
                       unit: "of \(UnitFormatter.effortScaleMax(UnitPrefs.resolveEffortScale(effortScaleRaw)))",
                       caption: strainCaption, tint: StrandPalette.effortColor)
                metric("HRV", icon: "waveform.path.ecg", value: hrv.map { number($0.value) } ?? "—", unit: "ms",
                       caption: hrv.map { sourceCaption($0, hrv: true) } ?? "Needs suitable R-R / sleep data",
                       tint: StrandPalette.chargeColor)
                metric("VO₂ max", icon: "lungs.fill", value: vo2.map { number($0) } ?? "—", unit: "mL/kg/min",
                       caption: vo2Caption, tint: StrandPalette.metricPurple)
                metric("Steps", icon: "figure.walk", value: steps.map { number($0.value) } ?? "—", unit: "",
                       caption: steps.map { sourceCaption($0) } ?? "No steps data today", tint: StrandPalette.metricCyan)
                metric("Resting HR", icon: "heart", value: restingHR.map { number($0.value) } ?? "—", unit: "bpm",
                       caption: restingHR.map { sourceCaption($0) } ?? "Needs resting heart-rate data",
                       tint: StrandPalette.metricRose)
            }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
        .onChange(of: repo.refreshSeq) { _, _ in Task { await load() } }
        .onChange(of: repo.deviceId) { _, _ in Task { await load() } }
        .onChange(of: dayCycleModeRaw) { _, _ in Task { await load() } }
    }

    @State private var restingHR: ResolvedMetricPoint?
    @State private var loadGeneration = 0

    private func metric(_ title: String, icon: String, value: String, unit: String,
                        caption: String, tint: Color) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Label(title, systemImage: icon).font(StrandFont.subhead).foregroundStyle(tint)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                    Text(value).font(StrandFont.number(32, weight: .bold)).foregroundStyle(StrandPalette.textPrimary)
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text(caption).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }

    private func sourceCaption(_ point: ResolvedMetricPoint, hrv: Bool = false) -> String {
        let provider: String
        if point.source == Repository.appleHealthSource {
            provider = hrv ? "Apple Health · SDNN" : "Apple Health"
        } else if point.source.hasSuffix("-noop") {
            provider = hrv ? "Local HRV · method unverified" : "On-device estimate"
        } else {
            provider = hrv ? "WHOOP record · rMSSD" : "WHOOP record"
        }
        return "\(provider) · \(point.day)"
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let now = Date()
        let id = repo.deviceId
        let calendarDay = Repository.localDayKey(now)
        let day = repo.today?.day ?? Repository.logicalDayKey(now)
        let logicalDate = Repository.logicalDay(now)
        let calendarStart = Int(Calendar.current.startOfDay(for: logicalDate).timeIntervalSince1970)
        let mode = DayCycleMode.persisted(dayCycleModeRaw)
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: Repository.whoopSource) : []
        let onset = markers.last { $0.day <= day && $0.value.isFinite && $0.value <= now.timeIntervalSince1970 }.map { Int($0.value.rounded()) }
        let from = mode == .sleepOnset ? onset ?? calendarStart : calendarStart
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: logicalDate) ?? logicalDate
        let nextKey = Repository.localDayKey(nextDate)
        let nextOnset = markers.last { $0.day == nextKey && $0.value.isFinite }.map { Int($0.value) }
        let end = min(Int(now.timeIntervalSince1970), nextOnset ?? Int(now.timeIntervalSince1970))
        async let hrRows = repo.hrSamples(from: from, to: max(from, end - 1), limit: 200_000)
        async let strains = repo.resolvedSeries(key: "strain", source: Repository.whoopSource, from: day, to: day)
        async let hrvs = repo.resolvedSeries(key: "hrv", source: Repository.whoopSource, days: 7)
        async let rests = repo.resolvedSeries(key: "rhr", source: Repository.whoopSource, days: 7)
        async let strapSteps = repo.resolvedSeries(key: "steps", source: Repository.whoopSource, from: calendarDay, to: calendarDay)
        async let appleSteps = repo.resolvedSeries(key: "steps", source: Repository.appleHealthSource, from: calendarDay, to: calendarDay)
        async let estimatedSteps = repo.resolvedSeries(key: "steps_est", source: Repository.whoopSource, from: calendarDay, to: calendarDay)
        async let vo2Estimates = repo.resolvedSeries(key: "vo2max_est", source: Repository.whoopSource, days: 30)
        async let appleVo2 = repo.resolvedSeries(key: "vo2max", source: Repository.appleHealthSource, days: 30)

        let rows = await hrRows
        let stored = (await strains).points.last { $0.day == day && $0.value.isFinite && $0.value >= 0 }
        let calculated = StrainScorer.strain(rows,
            maxHR: profile.effortHRmax,
            restingHR: repo.today?.day == day ? repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR : StrainScorer.defaultRestingHR,
            method: PuffinExperiment.effortMethod, sex: profile.sex)
        let newStrain = StrainScorer.effectiveEffort(live: calculated, stored: stored?.value)
        let newHrv = (await hrvs).points.last { $0.day <= day && $0.value.isFinite && $0.value > 0 }
        let newRest = (await rests).points.last { $0.day <= day && $0.value.isFinite && $0.value > 0 }
        let measuredSteps = (await strapSteps).points.last { $0.day == calendarDay && $0.value.isFinite && $0.value >= 0 }
        let importedSteps = (await appleSteps).points.last { $0.day == calendarDay && $0.value.isFinite && $0.value >= 0 }
        let fallbackSteps = (await estimatedSteps).points.last { $0.day == calendarDay && $0.value.isFinite && $0.value >= 0 }
        let newSteps = measuredSteps ?? importedSteps ?? fallbackSteps
        let apple = (await appleVo2).points.last { $0.day <= day && $0.value.isFinite && $0.value > 0 }
        let estimate = (await vo2Estimates).points.last { $0.day <= day && $0.value.isFinite && $0.value > 0 }
        var newVo2Caption = "No VO₂ max data yet"
        if let apple {
            newVo2Caption = "Apple Health · \(apple.day)"
        } else if let estimate {
            let tag = await repo.scoreProvenanceTag(resolvedSource: estimate.source, day: estimate.day, metricKey: "vo2max_est")
            let method = vo2MaxEstimatorDisplayName(tag.flatMap { Vo2MaxEstimator(rawValue: $0) })
            newVo2Caption = "Estimated · \(method) · \(estimate.day)"
        }
        guard generation == loadGeneration, id == repo.deviceId, calendarDay == Repository.localDayKey(Date()), !Task.isCancelled else { return }
        strain = newStrain
        strainCaption = newStrain == nil ? "Needs more heart-rate data"
            : calculated != nil && (stored?.value ?? 0) <= (calculated ?? 0) ? "Calculated from today's HR"
            : stored.map { sourceCaption($0) } ?? "Calculated on device"
        hrv = newHrv
        restingHR = newRest
        steps = newSteps
        vo2 = apple?.value ?? estimate?.value
        vo2Caption = newVo2Caption
    }
}
