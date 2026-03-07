import Foundation

enum TaskState: String, Codable, CaseIterable {
    case running
    case scheduled
    case paused
    case needsInput
    case completed
    case error
}

enum TaskScheduleType: String, Codable, CaseIterable {
    case manual
    case intervalMinutes
    case dailyAtHHMM
}

struct TaskRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var instructions: String
    var scheduleType: TaskScheduleType
    var scheduleValue: String
    var state: TaskState
    var provider: AuthProvider
    var providerThreadID: String?
    var personaId: String
    var runtimeMode: RuntimeMode
    var repoPath: String?
    var createdAt: Date
    var updatedAt: Date
    var lastRun: Date?
    var nextRun: Date?
    var lastError: String?

    var externalDirectoryPath: String? {
        get { repoPath }
        set { repoPath = newValue }
    }
}
