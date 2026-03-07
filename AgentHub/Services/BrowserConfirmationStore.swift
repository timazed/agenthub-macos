import Foundation

final class BrowserConfirmationStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("browser-confirmations.lock"))
    }

    func load() throws -> [BrowserConfirmationRecord] {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            guard fileManager.fileExists(atPath: paths.browserConfirmationsURL.path) else { return [] }
            let data = try Data(contentsOf: paths.browserConfirmationsURL)
            if data.isEmpty {
                return []
            }
            return try decoder.decode([BrowserConfirmationRecord].self, from: data)
        }
    }

    func save(_ confirmations: [BrowserConfirmationRecord]) throws {
        try lock.withLock {
            try saveUnlocked(confirmations)
        }
    }

    func upsert(_ confirmation: BrowserConfirmationRecord) throws {
        try lock.withLock {
            var records = try loadUnlocked()
            if let index = records.firstIndex(where: { $0.id == confirmation.id }) {
                records[index] = confirmation
            } else {
                records.append(confirmation)
            }
            try saveUnlocked(records)
        }
    }

    func pending(for sessionID: UUID) throws -> BrowserConfirmationRecord? {
        try load().last(where: { $0.sessionId == sessionID && $0.resolution == .pending })
    }

    private func loadUnlocked() throws -> [BrowserConfirmationRecord] {
        guard fileManager.fileExists(atPath: paths.browserConfirmationsURL.path) else { return [] }
        let data = try Data(contentsOf: paths.browserConfirmationsURL)
        if data.isEmpty {
            return []
        }
        return try decoder.decode([BrowserConfirmationRecord].self, from: data)
    }

    private func saveUnlocked(_ confirmations: [BrowserConfirmationRecord]) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(confirmations)
        try data.write(to: paths.browserConfirmationsURL, options: [.atomic])
    }
}
