import Foundation

enum VerifiedFileCopy {
    enum Failure: LocalizedError {
        case notAFile
        var errorDescription: String? { "The selected source or destination is not a regular file. The prepared file and previous destination are retained." }
    }

    /// Stage a copy before replacement; a failed source read never removes the previous destination.
    static func copy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let sourceInfo = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard sourceInfo.isRegularFile == true, sourceInfo.isSymbolicLink != true else { throw Failure.notAFile }
        if fm.fileExists(atPath: destination.path) {
            let targetInfo = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard targetInfo.isRegularFile == true, targetInfo.isSymbolicLink != true else { throw Failure.notAFile }
        }
        if source.standardizedFileURL == destination.standardizedFileURL { return }
        let staged = destination.deletingLastPathComponent().appendingPathComponent("dhoop-copy-\(UUID().uuidString).tmp")
        try fm.copyItem(at: source, to: staged)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staged)
        } else { try fm.moveItem(at: staged, to: destination) }
    }
}
