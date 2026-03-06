import Foundation

final class TaskRunStore {
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

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("task-runs.lock"))
    }

    func append(_ run: TaskRunRecord) throws {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if !fileManager.fileExists(atPath: paths.taskRunsURL.path) {
                try Data().write(to: paths.taskRunsURL, options: [.atomic])
            }

            var line = try encoder.encode(run)
            line.append(0x0A)
            let handle = try FileHandle(forWritingTo: paths.taskRunsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        }
    }

    func load(limit: Int = 100) throws -> [TaskRunRecord] {
        try lock.withLock {
            guard fileManager.fileExists(atPath: paths.taskRunsURL.path) else { return [] }
            let content = try String(contentsOf: paths.taskRunsURL)
            let values = content.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> TaskRunRecord? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(TaskRunRecord.self, from: data)
            }
            return Array(values.suffix(limit)).reversed()
        }
    }
}
