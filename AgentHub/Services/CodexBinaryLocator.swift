import Foundation

struct CodexBinaryLocator {
    private let binaryURLProvider: (() throws -> URL)?
    private let resourceURLProvider: () -> URL?
    private let fileManager: FileManager

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        binaryURLProvider: (() throws -> URL)? = nil
    ) {
        self.binaryURLProvider = binaryURLProvider
        self.resourceURLProvider = { bundle.resourceURL }
        self.fileManager = fileManager
    }

    init(
        binaryURLProvider: (() throws -> URL)? = nil,
        resourceURLProvider: @escaping () -> URL?,
        fileManager: FileManager = .default
    ) {
        self.binaryURLProvider = binaryURLProvider
        self.resourceURLProvider = resourceURLProvider
        self.fileManager = fileManager
    }

    func locateBinary() throws -> URL {
        if let binaryURLProvider {
            return try binaryURLProvider()
        }
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

        return candidates.first { isExecutableBinary(at: $0) }
    }

    private func isExecutableBinary(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return fileManager.isExecutableFile(atPath: url.path)
    }
}
