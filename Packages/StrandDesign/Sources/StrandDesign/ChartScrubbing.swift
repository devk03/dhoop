#if !os(watchOS)
import SwiftUI
import Charts

/// Coordinates chart gestures with ancestor navigation without adding a timer or a live data subscription.
@MainActor public enum ChartScrubActivity {
    private static var tokens = Set<UUID>()
    private static var releasedAt: TimeInterval = -.infinity
    public static var blocksNavigation: Bool { !tokens.isEmpty || ProcessInfo.processInfo.systemUptime - releasedAt < 0.3 }
    static func begin(_ token: UUID) { tokens.insert(token) }
    static func end(_ token: UUID) {
        if tokens.remove(token) != nil { releasedAt = ProcessInfo.processInfo.systemUptime }
    }
}

public extension View {
    /// Hold briefly, then drag. Immediate movement remains available to the surrounding scroll view.
    func chartTouchScrub(enabled: Bool = true, changed: @escaping (CGPoint?) -> Void) -> some View {
        modifier(ChartTouchScrubModifier(enabled: enabled, changed: changed))
    }
    /// Recorded-point access for charts that already supply their own visual crosshair.
    func chartInspectionAccessibility(_ index: ChartScrubIndex, label: String) -> some View {
        modifier(ChartInspectionAccessibility(index: index, label: label))
    }
    func chartInspectionAccessibility(_ data: [ChartScrubDatum], label: String) -> some View {
        modifier(ChartInspectionAccessibility(index: ChartScrubIndex(data), label: label))
    }
    func chartInspection(_ data: [ChartScrubDatum], dateAxis: Bool = true, label: String = "Chart", tint: Color = StrandPalette.accent, dailyBuckets: Bool = false, readoutBelow: Bool = false) -> some View {
        modifier(ChartInspectionModifier(data: data, dateAxis: dateAxis, label: label, tint: tint, dailyBuckets: dailyBuckets, readoutBelow: readoutBelow))
    }
}

private struct ChartTouchScrubModifier: ViewModifier {
    let enabled: Bool
    let changed: (CGPoint?) -> Void
    @State private var token = UUID()
    @GestureState private var held = false
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.2, maximumDistance: NoopMetrics.space2)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                .updating($held) { value, held, _ in
                    if case .second(true, _) = value { held = true }
                }
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }
                    ChartScrubActivity.begin(token)
                    if let drag {
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) { changed(drag.location) }
                    }
                }
                .onEnded { _ in ChartScrubActivity.end(token); changed(nil) }, including: enabled ? .all : .none)
            .onChange(of: held) { active in if !active { ChartScrubActivity.end(token); changed(nil) } }
            .onDisappear { ChartScrubActivity.end(token) }
        #else
        content
        #endif
    }
}

private struct ChartInspectionModifier: ViewModifier {
    let data: [ChartScrubDatum]
    let dateAxis: Bool
    let label: String
    let tint: Color
    let dailyBuckets: Bool
    let readoutBelow: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    let index: ChartScrubIndex
    @State private var selectedX: Double?
    init(data: [ChartScrubDatum], dateAxis: Bool, label: String, tint: Color, dailyBuckets: Bool, readoutBelow: Bool) {
        self.data = data; self.dateAxis = dateAxis; self.label = label; self.tint = tint; self.dailyBuckets = dailyBuckets
        self.index = ChartScrubIndex(data)
        self.readoutBelow = readoutBelow
    }
    func body(content: Content) -> some View {
        let index = index
        let selection = selectedX.flatMap { x in
            return index.selection(at: x, exact: dailyBuckets)
        }
        let inlineReadout = readoutBelow || typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
        content
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = proxy.plotRectCompat(in: geometry)
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle())
                        if let selection {
                            let rawDate = Date(timeIntervalSince1970: selection.x)
                            let bucketEnd = Calendar.current.date(byAdding: .day, value: 1, to: rawDate) ?? rawDate
                            let markerDate = dailyBuckets ? rawDate.addingTimeInterval(bucketEnd.timeIntervalSince(rawDate) / 2) : rawDate
                            let position = dateAxis ? proxy.position(forX: markerDate) : proxy.position(forX: selection.x)
                            if let rawPosition = position {
                                let position = min(plot.width, max(0, rawPosition))
                                CrosshairRule(x: plot.minX + position, height: plot.height).offset(y: plot.minY)
                                ForEach(selection.data) { datum in
                                    if let y = proxy.position(forY: datum.y) {
                                        HighlightDot(color: tint).position(x: plot.minX + position, y: plot.minY + y)
                                    }
                                }
                                if !inlineReadout {
                                    readout(selection)
                                        .frame(maxWidth: min(geometry.size.width, NoopMetrics.detailSheetMinWidth / 2), alignment: .leading)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .chartTouchScrub(enabled: !data.isEmpty) { location in select(location, proxy: proxy, plot: plot) }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): select(location, proxy: proxy, plot: plot)
                        case .ended: selectedX = nil
                        }
                    }
                }
            }
            if inlineReadout, let selection {
                readout(selection).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(selection.map { value in
                value.data.isEmpty ? "No recorded value on \(Date(timeIntervalSince1970: value.x).formatted(date: .abbreviated, time: .omitted))" : (value.isGap ? "Gap. Nearest recorded point. " : "") + value.data.map { "\($0.value), \($0.context)" }.joined(separator: ". ")
            } ?? "\(index.positions.count) recorded positions. Adjust to inspect values.")
            .accessibilityHint("Touch and hold, then drag to inspect. With VoiceOver, swipe up or down through recorded points.")
            .accessibilityAdjustableAction { direction in selectedX = index.adjacent(to: selectedX, forward: direction == .increment) }
            .accessibilityAction(named: Text("Clear selection")) { selectedX = nil }
            .onChange(of: data.map(\.id)) { _ in selectedX = nil }
    }
    private func readout(_ selection: ChartScrubSelection) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            if selection.data.isEmpty {
                Text("No recorded value").foregroundStyle(StrandPalette.textSecondary)
                Text(Date(timeIntervalSince1970: selection.x).formatted(date: .abbreviated, time: .omitted))
            } else if selection.isGap { Text("Gap · nearest recorded point").foregroundStyle(StrandPalette.textSecondary) }
            ForEach(selection.data) { datum in
                Text(datum.value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                Text(datum.context).foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .font(StrandFont.caption).fixedSize(horizontal: false, vertical: true)
        .padding(NoopMetrics.space2)
        .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: NoopMetrics.space2))
    }
    private func select(_ location: CGPoint?, proxy: ChartProxy, plot: CGRect) {
        guard let location, plot.contains(location) else { selectedX = nil; return }
        let relative = location.x - plot.minX
        if dateAxis {
            let date = proxy.value(atX: relative) as Date?
            selectedX = date.map { (dailyBuckets ? Calendar.current.startOfDay(for: $0) : $0).timeIntervalSince1970 }
        }
        else { selectedX = proxy.value(atX: relative) as Double? }
    }
}
private struct ChartInspectionAccessibility: ViewModifier {
    let index: ChartScrubIndex
    let label: String
    @State private var selectedX: Double?
    func body(content: Content) -> some View {
        content.accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue(selectedX.flatMap { index.selection(at: $0) }.map { $0.data.map { "\($0.value), \($0.context)" }.joined(separator: ". ") } ?? "\(index.positions.count) recorded positions. Adjust to inspect.")
            .accessibilityAdjustableAction { direction in selectedX = index.adjacent(to: selectedX, forward: direction == .increment) }
            .onChange(of: index.positions) { _ in selectedX = nil }
    }
}
#endif
