import Foundation

final class TaskStore {
    private struct LegacyScheduledTask: Codable {
        var id: UUID
        var name: String
        var prompt: String
        var personaId: String
        var mode: RuntimeMode
        var repoPath: String?
        var scheduleType: TaskScheduleType
        var scheduleValue: String
        var enabled: Bool
    }

    private let paths: AppPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock: FileLock

    init(paths: AppPaths, fileManager: FileManager = .default) throws {
        self.paths = paths
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("tasks.lock"))
        try bootstrap()
    }

    func load() throws -> [TaskRecord] {
        try lock.withLock {
            try loadUnlocked()
        }
    }

    func find(taskId: UUID) throws -> TaskRecord? {
        try load().first(where: { $0.id == taskId })
    }

    func save(_ tasks: [TaskRecord]) throws {
        try lock.withLock {
            try saveUnlocked(tasks)
        }
    }

    func upsert(_ task: TaskRecord) throws {
        try lock.withLock {
            var tasks = try loadUnlocked()
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            } else {
                tasks.append(task)
            }
            try saveUnlocked(tasks)
        }
    }

    func delete(taskId: UUID) throws {
        try lock.withLock {
            let tasks = try loadUnlocked().filter { $0.id != taskId }
            try saveUnlocked(tasks)
        }
    }

    func update(taskId: UUID, _ mutate: (inout TaskRecord) -> Void) throws -> TaskRecord {
        try lock.withLock {
            var tasks = try loadUnlocked()
            guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
                throw NSError(domain: "TaskStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
            }
            mutate(&tasks[index])
            tasks[index].updatedAt = Date()
            try saveUnlocked(tasks)
            return tasks[index]
        }
    }

    private func bootstrap() throws {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)
            if fileManager.fileExists(atPath: paths.taskListURL.path) {
                return
            }

            let legacyURL = paths.root.appendingPathComponent("schedules/tasks.json")
            if fileManager.fileExists(atPath: legacyURL.path),
               let data = try? Data(contentsOf: legacyURL),
               let legacy = try? decoder.decode([LegacyScheduledTask].self, from: data) {
                let migrated = legacy.map { value in
                    TaskRecord(
                        id: value.id,
                        title: value.name,
                        instructions: value.prompt,
                        scheduleType: value.scheduleType,
                        scheduleValue: value.scheduleValue,
                        state: value.enabled ? .scheduled : .paused,
                        codexThreadId: nil,
                        personaId: value.personaId,
                        runtimeMode: value.mode,
                        repoPath: value.repoPath,
                        createdAt: Date(),
                        updatedAt: Date(),
                        lastRun: nil,
                        nextRun: nil,
                        lastError: nil
                    )
                }
                try saveUnlocked(migrated)
                return
            }

            try saveUnlocked([])
        }
    }

    private func loadUnlocked() throws -> [TaskRecord] {
        guard fileManager.fileExists(atPath: paths.taskListURL.path) else { return [] }
        let data = try Data(contentsOf: paths.taskListURL)
        if data.isEmpty { return [] }
        return try decoder.decode([TaskRecord].self, from: data)
    }

    private func saveUnlocked(_ tasks: [TaskRecord]) throws {
        let data = try encoder.encode(tasks)
        try data.write(to: paths.taskListURL, options: [.atomic])
    }
}
