import SwiftUI
import Foundation
import StrandDesign
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - ProfileAvatarView
//
// The one reusable avatar element: renders the user's chosen on-device photo (Circle-cropped)
// if set, else the existing `person.crop.circle` SF Symbol fallback. Takes a `size` so the
// compact Today header and the large Settings row reuse the same view. Pure presentation — it's
// handed the stored JPEG bytes (`ProfileStore.avatarImageData`); it never touches storage.
//
// LOCAL-ONLY: the photo lives in UserDefaults on this device and is never uploaded (NOOP is
// fully offline). This view just draws whatever bytes it's given.

struct ProfileAvatarView: View {
    /// The stored profile photo bytes, or nil to show the default icon.
    var imageData: Data?
    /// Diameter in points (header ≈ 25–26, Settings ≈ 64).
    var size: CGFloat
    /// Icon tint for the fallback symbol (defaults to the header's secondary text tone).
    var fallbackTint: Color = StrandPalette.textSecondary

    init(imageData: Data?, size: CGFloat, fallbackTint: Color = StrandPalette.textSecondary) {
        self.imageData = imageData
        self.size = size
        self.fallbackTint = fallbackTint
    }

    var body: some View {
        if let image = decodedImage {
            image
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                // A faint hairline ring so the photo edge reads cleanly on any card/canvas.
                .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: 1))
        } else {
            // Fallback: the NOOP loop BrandMark (the green ring + white core) instead of a generic
            // person glyph — the default avatar is now on-brand. BrandMark is intrinsically square and
            // sized off a single edge length, so it fills the same `size` footprint a photo / the old
            // symbol did, keeping the header and Settings layouts unchanged.
            BrandMark(size: size)
                .frame(width: size, height: size)
        }
    }

    /// Decode the stored bytes through the platform bitmap type (`NSImage`/`UIImage`) into a
    /// SwiftUI `Image` via the shared `Image(platformImage:)` bridge. nil on no data / bad bytes.
    private var decodedImage: Image? {
        guard let imageData, let platform = AvatarImage.displayableImage(from: imageData) else { return nil }
        return Image(platformImage: platform)
    }
}

// MARK: - Avatar downscaling
//
// Shrinks a picked photo to a small square JPEG before it's persisted, so the UserDefaults blob
// stays tiny (a full-res phone photo would be megabytes). Built on ImageIO/CoreGraphics, which are
// identical across macOS and iOS — no UIKit/AppKit divergence in the resize path.

enum AvatarImage {
    /// A recognized raster must decode through ImageIO; retain native-format fallback only when
    /// ImageIO has no decoder. A lazy platform object cannot rescue a failed raster decode.
    static func importData(from data: Data, maxDimension: CGFloat, quality: CGFloat = 0.8) -> Data? {
        if let jpeg = downscaledJPEG(from: data, maxDimension: maxDimension, quality: quality) { return jpeg }
        if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) != nil { return nil }
        guard displayableImage(from: data) != nil else { return nil }
        return data
    }

    /// Platform construction can accept only a header; require renderable pixels before commit.
    static func displayableImage(from data: Data) -> PlatformImage? {
        guard let image = PlatformImage(data: data) else { return nil }
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceThumbnailMaxPixelSize: 256]
            guard CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil else { return nil }
        }
        #if canImport(AppKit)
        guard image.isValid, image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else { return nil }
        #elseif canImport(UIKit)
        guard image.cgImage != nil || image.ciImage != nil else { return nil }
        #endif
        return image
    }

    /// Downscale `data` so its longest side is at most `maxDimension` points and re-encode as JPEG.
    /// Returns nil if the bytes can't be decoded (caller may fall back to the raw bytes).
    /// - `maxDimension`: the cap on the longest edge (default 256 — plenty for a circle-cropped avatar).
    /// - `quality`: JPEG quality 0...1.
    static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 256, quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        guard CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
        let out = NSMutableData()
        let type = UTType.jpeg.identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

#if DEBUG
#Preview("ProfileAvatar") {
    VStack(spacing: 24) {
        // Fallback (no photo) at header + Settings sizes.
        HStack(spacing: 24) {
            ProfileAvatarView(imageData: nil, size: 26)
            ProfileAvatarView(imageData: nil, size: 64)
        }
        Text("No photo → person.crop.circle fallback")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
    }
    .padding(40)
    .frame(width: 360, height: 240)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
