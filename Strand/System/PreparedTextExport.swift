import Foundation

enum PreparedTextExport {
    enum Failure: LocalizedError {
        case invalidName
        var errorDescription: String? { "The export filename must name one file. No prepared file was replaced." }
    }

    /// Each preparation owns a distinct directory; retries keep earlier readable exports intact.
    static func write(_ text: String, suggestedName: String,
                      directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard !suggestedName.isEmpty, suggestedName != ".", suggestedName != "..",
              URL(fileURLWithPath: suggestedName).lastPathComponent == suggestedName else {
            throw Failure.invalidName
        }
        let folder = directory.appendingPathComponent("dhoop-text-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(suggestedName)
        try Data(text.utf8).write(to: file, options: .atomic)
        return file
    }
}
