import Foundation

final class AuthStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("auth.lock"))
    }

    func loadOrCreateDefault(provider: AuthProvider = .codex) throws -> AuthState {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            let authURL = paths.authStateURL(for: provider)
            if fileManager.fileExists(atPath: authURL.path) {
                return try loadUnlocked(provider: provider)
            }

            if provider == .codex, fileManager.fileExists(atPath: paths.legacyAuthStateURL.path) {
                let state = try loadLegacyCurrentUnlocked()
                try saveUnlocked(state)
                return state
            }

            if provider == .codex, fileManager.fileExists(atPath: paths.legacyCodexAuthStateURL.path) {
                let state = try loadLegacyUnlocked()
                try saveUnlocked(state)
                return state
            }

            let state = AuthState.default(provider: provider)
            try saveUnlocked(state)
            return state
        }
    }

    func load(provider: AuthProvider = .codex) throws -> AuthState {
        try lock.withLock {
            try loadUnlocked(provider: provider)
        }
    }

    func save(_ state: AuthState) throws {
        try lock.withLock {
            try saveUnlocked(state)
        }
    }

    private func loadUnlocked(provider: AuthProvider) throws -> AuthState {
        let data = try Data(contentsOf: paths.authStateURL(for: provider))
        return try decoder.decode(AuthState.self, from: data)
    }

    private func loadLegacyCurrentUnlocked() throws -> AuthState {
        let data = try Data(contentsOf: paths.legacyAuthStateURL)
        return try decoder.decode(AuthState.self, from: data)
    }

    private func loadLegacyUnlocked() throws -> AuthState {
        let data = try Data(contentsOf: paths.legacyCodexAuthStateURL)
        let legacy = try decoder.decode(LegacyCodexAuthState.self, from: data)
        return AuthState(
            provider: .codex,
            status: legacy.status,
            accountLabel: legacy.accountEmail,
            lastValidatedAt: legacy.lastValidatedAt,
            failureReason: legacy.failureReason,
            updatedAt: legacy.updatedAt
        )
    }

    private func saveUnlocked(_ state: AuthState) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(state)
        try data.write(to: paths.authStateURL(for: state.provider), options: [.atomic])
    }
}

private struct LegacyCodexAuthState: Codable {
    var status: AuthenticationStatus
    var accountEmail: String?
    var lastValidatedAt: Date?
    var failureReason: String?
    var updatedAt: Date
}
