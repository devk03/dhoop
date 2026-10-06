#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest
@testable import StrandDesign

@MainActor
final class PrimaryButtonContrastTests: XCTestCase {
    func testNeutralPrimaryLabelsRemainReadableInBothAppearances() throws {
        let saved = StrandPalette.accentChoice
        defer { StrandPalette.accentChoice = saved }
        StrandPalette.accentChoice = .neutral
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var contrast: Double = 0
            appearance.performAsCurrentDrawingAppearance {
                let primary = NoopButtonAppearance(.primary)
                guard let fill = primary.fill,
                      let ink = NSColor(primary.label).usingColorSpace(.sRGB),
                      let background = NSColor(fill).usingColorSpace(.sRGB) else { return }
                func luminance(_ color: NSColor) -> Double {
                    func linear(_ value: CGFloat) -> Double {
                        let v = Double(value)
                        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                    }
                    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
                }
                let a = luminance(ink), b = luminance(background)
                contrast = (max(a, b) + 0.05) / (min(a, b) + 0.05)
            }
            XCTAssertGreaterThanOrEqual(contrast, 7, "Primary button contrast in \(name)")
        }
    }
    func testSwitchTrackSeparatesFromTheNativeWhiteThumb() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var ratio: Double = 0
            appearance.performAsCurrentDrawingAppearance {
                guard let track = NSColor(NoopVisualStyle.switchTint).usingColorSpace(.sRGB) else { return }
                func linear(_ component: CGFloat) -> Double {
                    let value = Double(component)
                    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear(track.redComponent) + 0.7152 * linear(track.greenComponent) + 0.0722 * linear(track.blueComponent)
                ratio = 1.05 / (luminance + 0.05)
            }
            XCTAssertGreaterThanOrEqual(ratio, 3, "Switch thumb contrast in \(name)")
        }
    }

}
#endif
