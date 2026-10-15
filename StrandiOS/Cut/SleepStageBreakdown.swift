import SwiftUI
import StrandDesign

/// Dated, source-separated stage rows remain visible without an expansion gesture.
struct SleepStageBreakdown: View {
    enum Kind: String, CaseIterable {
        case deep = "Deep", rem = "REM", light = "Light", unclassified = "Unclassified"
        var color: Color {
            switch self {
            case .deep: return StrandChartStyle.stageDeep
            case .rem: return StrandChartStyle.stageREM
            case .light: return StrandChartStyle.stageLight
            case .unclassified: return StrandPalette.textTertiary
            }
        }
    }
    struct Row: Identifiable {
        let kind: Kind
        let duration: String
        let fraction: Double?
        var id: String { kind.rawValue }
    }
    struct Source: Identifiable {
        let name: String
        let detail: String
        let rows: [Row]
        var id: String { name }
    }
    let dateLabel: String
    let sources: [Source]
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("Stage breakdown").font(StrandFont.headline)
                Text(dateLabel).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                ForEach(sources) { source in
                    if source.id != sources.first?.id { Divider() }
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text(source.name).font(StrandFont.subhead)
                        ForEach(source.rows) { row in
                            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: NoopMetrics.space2) {
                                        Label(row.kind.rawValue, systemImage: "circle.fill").foregroundStyle(row.kind.color)
                                        Spacer(minLength: NoopMetrics.space2)
                                        amount(row)
                                    }
                                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                                        Label(row.kind.rawValue, systemImage: "circle.fill").foregroundStyle(row.kind.color)
                                        amount(row)
                                    }
                                }.font(StrandFont.subhead)
                                if let fraction = row.fraction { NoopProgressTrack(fraction: fraction, tint: row.kind.color) }
                            }.accessibilityElement(children: .combine)
                        }
                        Text(source.detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }
    private func amount(_ row: Row) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            Text(row.duration).monospacedDigit()
            if let fraction = row.fraction {
                Text("\(Int((fraction * 100).rounded()))%").monospacedDigit().foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}
