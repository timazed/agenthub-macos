import Foundation

final class OnboardingStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("onboarding.lock"))
    }

    func loadOrCreateDefault() throws -> OnboardingState {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)

            if fileManager.fileExists(atPath: paths.onboardingStateURL.path) {
                return try loadUnlocked()
            }

            let state = OnboardingState.default()
            try saveUnlocked(state)
            return state
        }
    }

    func save(_ state: OnboardingState) throws {
        try lock.withLock {
            try saveUnlocked(state)
        }
    }

    private func loadUnlocked() throws -> OnboardingState {
        let data = try Data(contentsOf: paths.onboardingStateURL)
        return try decoder.decode(OnboardingState.self, from: data)
    }

    private func saveUnlocked(_ state: OnboardingState) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(state)
        try data.write(to: paths.onboardingStateURL, options: [.atomic])
    }
}
