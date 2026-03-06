import Foundation

final class WorkspaceManager {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validateExternalDirectory(path: String?, for mode: RuntimeMode) throws -> String? {
        switch mode {
        case .chatOnly:
            return nil
        case .task:
            guard let path, !path.isEmpty else { return nil }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw NSError(domain: "WorkspaceManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "External directory does not exist: \(path)"])
            }
            guard fileManager.isReadableFile(atPath: path) else {
                throw NSError(domain: "WorkspaceManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "External directory is not readable: \(path)"])
            }
            guard fileManager.isWritableFile(atPath: path) else {
                throw NSError(domain: "WorkspaceManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "External directory is not writable: \(path)"])
            }
            return path
        }
    }

    func validate(path: String?, for mode: RuntimeMode) throws -> String? {
        try validateExternalDirectory(path: path, for: mode)
    }
}
