import Foundation

struct BrowserRegistryDocument: Codable, Hashable {
    var profiles: [BrowserProfileRecord]
    var policies: [BrowserPolicyRecord]
    var updatedAt: Date

    static func `default`() -> BrowserRegistryDocument {
        let profile = BrowserProfileRecord.default()
        return BrowserRegistryDocument(
            profiles: [profile],
            policies: [.default(profileId: profile.profileId, displayName: profile.displayName)],
            updatedAt: Date()
        )
    }
}

final class BrowserPolicyRegistry {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("browser-registry.lock"))
    }

    func loadOrCreateDefault() throws -> BrowserRegistryDocument {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            guard fileManager.fileExists(atPath: paths.browserRegistryURL.path) else {
                let document = BrowserRegistryDocument.default()
                try saveUnlocked(document)
                return document
            }

            return try loadUnlocked()
        }
    }

    func save(_ document: BrowserRegistryDocument) throws {
        try lock.withLock {
            try saveUnlocked(document)
        }
    }

    func profile(for profileId: String) throws -> BrowserProfileRecord? {
        try loadOrCreateDefault().profiles.first(where: { $0.profileId == profileId })
    }

    func policy(for profileId: String) throws -> BrowserPolicyRecord? {
        try loadOrCreateDefault().policies.first(where: { $0.profileId == profileId })
    }

    private func loadUnlocked() throws -> BrowserRegistryDocument {
        let data = try Data(contentsOf: paths.browserRegistryURL)
        return try decoder.decode(BrowserRegistryDocument.self, from: data)
    }

    private func saveUnlocked(_ document: BrowserRegistryDocument) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try encoder.encode(document)
        try data.write(to: paths.browserRegistryURL, options: [.atomic])
    }
}
