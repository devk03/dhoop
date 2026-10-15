#if os(iOS)
import SwiftUI
import StrandDesign

struct WorkoutTrackerRoutinesView: View {
    var embedded = false
    var body: some View {
        if embedded { StrengthDashboardView() }
        else { ScreenScaffold(title: "Strength") { StrengthDashboardView() } }
    }
}
#endif
