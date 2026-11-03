#if os(iOS)
import SwiftUI
import UIKit
import ImageIO
import StrandDesign

/// Originals stay in their existing protected store. Display previews are downsampled in memory only.
enum HealthJournalPhotoSource {
    case remote(HealthJournalImage)
    case local(HealthJournalPendingPhoto)
    var identity: String {
        switch self {
        case .remote(let image): return "remote|" + image.id + "|" + image.sha256
        case .local(let photo): return "local|" + photo.id + "|" + photo.sha256
        }
    }
}
@MainActor
enum HealthJournalPreviews {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.countLimit = 48; cache.totalCostLimit = 20 * 1024 * 1024
        return cache
    }()
    static func clear() { cache.removeAllObjects() }
    static func image(_ source: HealthJournalPhotoSource, client: HealthJournalClient) async throws -> UIImage {
        let scope = String(describing: ObjectIdentifier(client)), key = (scope + "|" + source.identity) as NSString
        if let image = cache.object(forKey: key) { return image }
        let bytes: Data
        switch source {
        case .remote(let image): bytes = try await client.image(image)
        case .local(let photo): bytes = try await client.localPhoto(photo)
        }
        try Task.checkCancellation()
        let image = try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw HealthJournalFailure.invalidResponse }
            return UIImage(cgImage: decoded)
        }.value
        try Task.checkCancellation()
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
struct HealthJournalThumbnail: View {
    @ObservedObject var client: HealthJournalClient
    let source: HealthJournalPhotoSource
    @State private var preview: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            StrandPalette.surfaceInset
            if let preview { Image(uiImage: preview).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(StrandPalette.textSecondary) }
            else { ProgressView().tint(StrandPalette.metricPurple) }
        }
        .frame(width: NoopMetrics.healthJournalThumbnailSize, height: NoopMetrics.healthJournalThumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: NoopVisualStyle.compactRadius))
        .accessibilityHidden(true)
        .task(id: source.identity) {
            preview = nil; failed = false
            do { preview = try await HealthJournalPreviews.image(source, client: client) }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

/// Camera capture is initiated only by the owner's Camera action, never by opening the journal.
struct HealthJournalCamera: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}
#endif
