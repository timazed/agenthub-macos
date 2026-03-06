import Foundation

final class CodexAuthStore {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock: FileLock

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("codex-auth.lock"))
    }

    func loadOrCreateDefault() throws -> CodexAuthState {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if fileManager.fileExists(atPath: paths.codexAuthStateURL.path) {
                return try loadUnlocked()
            }

            let state = CodexAuthState.default()
            try saveUnlocked(state)
            return state
        }
    }

    func load() throws -> CodexAuthState {
        try lock.withLock {
            try loadUnlocked()
        }
    }

    func save(_ state: CodexAuthState) throws {
        try lock.withLock {
            try saveUnlocked(state)
        }
    }

    private func loadUnlocked() throws -> CodexAuthState {
        let data = try Data(contentsOf: paths.codexAuthStateURL)
        return try decoder.decode(CodexAuthState.self, from: data)
    }

    private func saveUnlocked(_ state: CodexAuthState) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(state)
        try data.write(to: paths.codexAuthStateURL, options: [.atomic])
    }
}
