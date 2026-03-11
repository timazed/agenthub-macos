import Foundation

struct CodexBinaryLocator {
    private let resourceURLProvider: () -> URL?
    private let fileManager: FileManager

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.resourceURLProvider = { bundle.resourceURL }
        self.fileManager = fileManager
    }

    init(
        resourceURLProvider: @escaping () -> URL?,
        fileManager: FileManager = .default
    ) {
        self.resourceURLProvider = resourceURLProvider
        self.fileManager = fileManager
    }

    func locateBinary() throws -> URL {
        if let bundledBinary = bundledBinaryURL() {
            return bundledBinary
        }

        throw AssistantRuntimeError.binaryNotFound
    }

    func locateBinaryPath() -> String {
        (try? locateBinary().path) ?? "<missing bundled codex>"
    }

    private func bundledBinaryURL() -> URL? {
        guard let resourcesURL = resourceURLProvider() else { return nil }

        let candidates = [
            resourcesURL.appendingPathComponent("codex", isDirectory: false),
            resourcesURL.appendingPathComponent("codex/codex", isDirectory: false),
        ]

        return candidates.first { candidate in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return false
            }

            return fileManager.isExecutableFile(atPath: candidate.path)
        }
    }
}
