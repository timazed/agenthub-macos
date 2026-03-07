import Foundation

final class BrowserActionLogStore {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock: FileLock

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("browser-action-log.lock"))
    }

    func append(_ record: BrowserActionRecord) throws {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if !fileManager.fileExists(atPath: paths.browserActionLogURL.path) {
                try Data().write(to: paths.browserActionLogURL, options: [.atomic])
            }

            var line = try encoder.encode(record)
            line.append(0x0A)
            let handle = try FileHandle(forWritingTo: paths.browserActionLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        }
    }

    func load(limit: Int = 100) throws -> [BrowserActionRecord] {
        try lock.withLock {
            guard fileManager.fileExists(atPath: paths.browserActionLogURL.path) else { return [] }
            let content = try String(contentsOf: paths.browserActionLogURL)
            let records = content.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> BrowserActionRecord? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(BrowserActionRecord.self, from: data)
            }
            return Array(records.suffix(limit)).reversed()
        }
    }
}
