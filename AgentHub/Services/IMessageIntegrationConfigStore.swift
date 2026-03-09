import Foundation

final class IMessageIntegrationConfigStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("imessage-integration-config.lock"))
    }

    func loadOrCreateDefault() throws -> IMessageIntegrationConfig {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if fileManager.fileExists(atPath: paths.iMessageIntegrationConfigURL.path) {
                return try loadUnlocked()
            }

            let config = IMessageIntegrationConfig.default()
            try saveUnlocked(config)
            return config
        }
    }

    func save(_ config: IMessageIntegrationConfig) throws {
        try lock.withLock {
            try saveUnlocked(config)
        }
    }

    private func loadUnlocked() throws -> IMessageIntegrationConfig {
        let data = try Data(contentsOf: paths.iMessageIntegrationConfigURL)
        return try decoder.decode(IMessageIntegrationConfig.self, from: data)
    }

    private func saveUnlocked(_ config: IMessageIntegrationConfig) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(config)
        try data.write(to: paths.iMessageIntegrationConfigURL, options: [.atomic])
    }
}
