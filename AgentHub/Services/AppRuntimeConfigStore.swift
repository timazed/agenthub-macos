import Foundation

final class AppRuntimeConfigStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("runtime-config.lock"))
    }

    func loadOrCreateDefault() throws -> AppRuntimeConfig {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if fileManager.fileExists(atPath: paths.runtimeConfigURL.path) {
                return try loadUnlocked()
            }

            let config = AppRuntimeConfig.default()
            try saveUnlocked(config)
            return config
        }
    }

    func save(_ config: AppRuntimeConfig) throws {
        try lock.withLock {
            try saveUnlocked(config)
        }
    }

    private func loadUnlocked() throws -> AppRuntimeConfig {
        let data = try Data(contentsOf: paths.runtimeConfigURL)
        return try decoder.decode(AppRuntimeConfig.self, from: data)
    }

    private func saveUnlocked(_ config: AppRuntimeConfig) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(config)
        try data.write(to: paths.runtimeConfigURL, options: [.atomic])
    }
}
