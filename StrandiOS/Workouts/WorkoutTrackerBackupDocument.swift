#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let dhoopWorkoutMetadata = UTType(exportedAs: "com.dhoop.workout-metadata", conformingTo: .package)
}

struct WorkoutTrackerBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.dhoopWorkoutMetadata] }
    private let wrapper: FileWrapper
    init(package: URL) throws { wrapper = try FileWrapper(url: package, options: []) }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}
#endif
