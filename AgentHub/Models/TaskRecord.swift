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

    init(
        id: UUID,
        title: String,
        instructions: String,
        scheduleType: TaskScheduleType,
        scheduleValue: String,
        state: TaskState,
        provider: AuthProvider,
        providerThreadID: String?,
        personaId: String,
        runtimeMode: RuntimeMode,
        repoPath: String?,
        createdAt: Date,
        updatedAt: Date,
        lastRun: Date?,
        nextRun: Date?,
        lastError: String?
    ) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.scheduleType = scheduleType
        self.scheduleValue = scheduleValue
        self.state = state
        self.provider = provider
        self.providerThreadID = providerThreadID
        self.personaId = personaId
        self.runtimeMode = runtimeMode
        self.repoPath = repoPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRun = lastRun
        self.nextRun = nextRun
        self.lastError = lastError
    }

    var externalDirectoryPath: String? {
        get { repoPath }
        set { repoPath = newValue }
    }
}
