#if !os(watchOS)
import SwiftUI
import Charts
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

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
    func chartInspection(_ data: [ChartScrubDatum], dateAxis: Bool = true, label: String = "Chart", tint: Color = StrandPalette.accent, dailyBuckets: Bool = false, readoutBelow _: Bool = false, compactReadout: Bool = false, bucketUnit: Calendar.Component? = nil) -> some View {
        modifier(ChartInspectionModifier(data: data, dateAxis: dateAxis, label: label, tint: tint, bucketUnit: bucketUnit ?? (dailyBuckets ? .day : nil), compactReadout: compactReadout))
    }
}

private struct ChartTouchScrubModifier: ViewModifier {
    let enabled: Bool
    let changed: (CGPoint?) -> Void
    func body(content: Content) -> some View {
        #if os(iOS)
        content.overlay { ChartHoldSurface(enabled: enabled, changed: changed) }
        #else
        content
        #endif
    }
}

#if canImport(UIKit) && os(iOS)
/// A single native hold recognizer never reserves an immediate drag from the enclosing scroll view.
private struct ChartHoldSurface: UIViewRepresentable {
    let enabled: Bool
    let changed: (CGPoint?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(changed: changed) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        hold.minimumPressDuration = 0.3
        hold.allowableMovement = NoopMetrics.space2
        hold.cancelsTouchesInView = false
        hold.delaysTouchesBegan = false
        hold.delaysTouchesEnded = false
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.changed = changed
        view.isUserInteractionEnabled = enabled
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.finish() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var changed: (CGPoint?) -> Void
        private let token = UUID()
        private var active = false
        private var origin: CGPoint?
        init(changed: @escaping (CGPoint?) -> Void) { self.changed = changed }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func handle(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                let point = gesture.location(in: gesture.view)
                if gesture.state == .began { origin = point }
                if let origin, gesture.state == .changed {
                    let dx = abs(point.x - origin.x), dy = abs(point.y - origin.y)
                    if dy > NoopMetrics.space2 && dy > dx {
                        // Vertical intent belongs to the already-co-recognizing scroll pan.
                        finish()
                        gesture.isEnabled = false; gesture.isEnabled = true
                        return
                    }
                }
                if !active { active = true; ChartScrubActivity.begin(token) }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { changed(point) }
            case .ended, .cancelled, .failed: finish()
            default: break
            }
        }
        func finish() {
            guard active else { return }
            active = false
            origin = nil
            ChartScrubActivity.end(token)
            changed(nil)
        }
    }
}
#endif

private struct ChartInspectionModifier: ViewModifier {
    let data: [ChartScrubDatum]
    let dateAxis: Bool
    let label: String
    let tint: Color
    let bucketUnit: Calendar.Component?
    let compactReadout: Bool
    let index: ChartScrubIndex
    @State private var selectedX: Double?
    init(data: [ChartScrubDatum], dateAxis: Bool, label: String, tint: Color, bucketUnit: Calendar.Component?, compactReadout: Bool) {
        self.data = data; self.dateAxis = dateAxis; self.label = label; self.tint = tint; self.bucketUnit = bucketUnit
        self.index = ChartScrubIndex(data)
        self.compactReadout = compactReadout
    }
    func body(content: Content) -> some View {
        let index = index
        let selection = selectedX.flatMap { x in
            return index.selection(at: x, bucketUnit: bucketUnit)
        }
        content
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = proxy.plotRectCompat(in: geometry)
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle())
                        if let selection {
                            let rawDate = Date(timeIntervalSince1970: selection.x)
                            let bucketEnd = Calendar.current.date(byAdding: bucketUnit ?? .day, value: 1, to: rawDate) ?? rawDate
                            let markerDate = bucketUnit != nil ? rawDate.addingTimeInterval(bucketEnd.timeIntervalSince(rawDate) / 2) : rawDate
                            let position = dateAxis ? proxy.position(forX: markerDate) : proxy.position(forX: selection.x)
                            if let rawPosition = position {
                                let position = min(plot.width, max(0, rawPosition))
                                CrosshairRule(x: plot.minX + position, height: plot.height).offset(y: plot.minY)
                                ForEach(selection.data) { datum in
                                    if let y = proxy.position(forY: datum.y) {
                                        HighlightDot(color: tint).position(x: plot.minX + position, y: plot.minY + y)
                                    }
                                }
                                readout(selection)
                                    .frame(maxWidth: geometry.size.width, alignment: .leading)
                                    .allowsHitTesting(false)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(selection.map { value in
                value.data.isEmpty ? "No recorded value on \(Date(timeIntervalSince1970: value.x).formatted(date: .abbreviated, time: bucketUnit == .hour ? .shortened : .omitted))" : (value.isGap ? "Gap. Nearest recorded point. " : "") + value.data.map { "\($0.value), \($0.context)" }.joined(separator: ". ")
            } ?? "\(index.positions.count) recorded positions. Adjust to inspect values.")
            .accessibilityHint("Touch and hold, then drag to inspect. With VoiceOver, swipe up or down through recorded points.")
            .accessibilityAdjustableAction { direction in selectedX = index.adjacent(to: selectedX, forward: direction == .increment) }
            .accessibilityAction(named: Text("Clear selection")) { selectedX = nil }
            .onChange(of: data.map(\.id)) { _ in selectedX = nil }
    }
    @ViewBuilder private func readout(_ selection: ChartScrubSelection) -> some View {
        if compactReadout, let datum = selection.data.first {
            HStack(spacing: NoopMetrics.space1) {
                Text(datum.y.formatted(.number.precision(.fractionLength(0...1)))).font(StrandFont.captionNumber)
                Spacer(minLength: NoopMetrics.space1)
                Text(Date(timeIntervalSince1970: datum.x), format: .dateTime.month(.abbreviated).day())
                    .font(StrandFont.caption)
            }
            .foregroundStyle(StrandPalette.textPrimary).lineLimit(1)
            .padding(NoopMetrics.space1)
            .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: NoopMetrics.space1))
        } else {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            if selection.data.isEmpty {
                Text("No recorded value").foregroundStyle(StrandPalette.textSecondary)
                Text(Date(timeIntervalSince1970: selection.x).formatted(date: .abbreviated, time: bucketUnit == .hour ? .shortened : .omitted))
            } else if selection.isGap { Text("Gap · nearest recorded point").foregroundStyle(StrandPalette.textSecondary) }
            ForEach(selection.data) { datum in
                Text(datum.value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                Text(datum.context).foregroundStyle(StrandPalette.textSecondary).lineLimit(2)
            }
        }
        .font(StrandFont.caption).fixedSize(horizontal: false, vertical: true)
        .padding(NoopMetrics.space2)
        .background(StrandPalette.surfaceOverlay, in: RoundedRectangle(cornerRadius: NoopMetrics.space2))
        }
    }
    private func select(_ location: CGPoint?, proxy: ChartProxy, plot: CGRect) {
        guard let location, plot.contains(location) else { selectedX = nil; return }
        let relative = location.x - plot.minX
        if dateAxis {
            let date = proxy.value(atX: relative) as Date?
            selectedX = date.map { $0.timeIntervalSince1970 }
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
