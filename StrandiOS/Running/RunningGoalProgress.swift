import SwiftUI
import StrandDesign

struct RunningGoalProgress: View {
    let credited: Double
    let goal: Double
    let completed: Bool
    private var fraction: Double { credited.isFinite && goal.isFinite && goal > 0 ? min(1, max(0, credited / goal)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceInset)
                Capsule().fill(completed ? StrandPalette.metricPurple : StrandPalette.metricAmber)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: NoopMetrics.space3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time-in-range goal progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
