import Foundation

final class ActivityLogStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("activity.lock"))
    }

    func append(_ event: ActivityEvent) throws {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if !fileManager.fileExists(atPath: paths.activityLogURL.path) {
                try Data().write(to: paths.activityLogURL, options: [.atomic])
            }

            var line = try encoder.encode(event)
            line.append(0x0A)
            let handle = try FileHandle(forWritingTo: paths.activityLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        }
    }

    func load(limit: Int = 200) throws -> [ActivityEvent] {
        try lock.withLock {
            guard fileManager.fileExists(atPath: paths.activityLogURL.path) else { return [] }
            let content = try String(contentsOf: paths.activityLogURL)
            let events = content.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> ActivityEvent? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(ActivityEvent.self, from: data)
            }
            return Array(events.suffix(limit)).reversed()
        }
    }
}
