import Foundation

struct CodexBinaryLocator {
    private let resourceURLProvider: () -> URL?
    private let currentDirectoryURLProvider: () -> URL
    private let fileManager: FileManager

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        currentDirectoryURLProvider: @escaping () -> URL = {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        }
    ) {
        self.resourceURLProvider = { bundle.resourceURL }
        self.currentDirectoryURLProvider = currentDirectoryURLProvider
        self.fileManager = fileManager
    }

    init(
        resourceURLProvider: @escaping () -> URL?,
        currentDirectoryURLProvider: @escaping () -> URL,
        fileManager: FileManager = .default
    ) {
        self.resourceURLProvider = resourceURLProvider
        self.currentDirectoryURLProvider = currentDirectoryURLProvider
        self.fileManager = fileManager
    }

    func locateBinary(allowWorkspaceFallback: Bool = false) throws -> URL {
        if let bundledBinary = bundledBinaryURL() {
            return bundledBinary
        }

        if allowWorkspaceFallback, let workspaceBinary = workspaceBinaryURL() {
            return workspaceBinary
        }

        throw AssistantRuntimeError.binaryNotFound
    }

    func locateBinaryPath(allowWorkspaceFallback: Bool = false) -> String {
        (try? locateBinary(allowWorkspaceFallback: allowWorkspaceFallback).path) ?? "<missing bundled codex>"
    }

    private func bundledBinaryURL() -> URL? {
        guard let resourcesURL = resourceURLProvider() else { return nil }

        let candidates = [
            resourcesURL.appendingPathComponent("codex", isDirectory: false),
            resourcesURL.appendingPathComponent("codex/codex", isDirectory: false),
        ]

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func workspaceBinaryURL() -> URL? {
        let workspaceCandidate = currentDirectoryURLProvider()
            .appendingPathComponent("AgentHub/Resources/codex/codex", isDirectory: false)
        guard fileManager.isExecutableFile(atPath: workspaceCandidate.path) else {
            return nil
        }
        return workspaceCandidate
    }
}
