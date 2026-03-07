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

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case instructions
        case scheduleType
        case scheduleValue
        case state
        case provider
        case providerThreadID
        case codexThreadId
        case personaId
        case runtimeMode
        case repoPath
        case createdAt
        case updatedAt
        case lastRun
        case nextRun
        case lastError
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        instructions = try container.decode(String.self, forKey: .instructions)
        scheduleType = try container.decode(TaskScheduleType.self, forKey: .scheduleType)
        scheduleValue = try container.decode(String.self, forKey: .scheduleValue)
        state = try container.decode(TaskState.self, forKey: .state)
        provider = try container.decodeIfPresent(AuthProvider.self, forKey: .provider) ?? .codex
        let providerThread = try container.decodeIfPresent(String.self, forKey: .providerThreadID)
        let legacyThread = try container.decodeIfPresent(String.self, forKey: .codexThreadId)
        providerThreadID = providerThread ?? legacyThread
        personaId = try container.decode(String.self, forKey: .personaId)
        runtimeMode = try container.decode(RuntimeMode.self, forKey: .runtimeMode)
        repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastRun = try container.decodeIfPresent(Date.self, forKey: .lastRun)
        nextRun = try container.decodeIfPresent(Date.self, forKey: .nextRun)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(scheduleType, forKey: .scheduleType)
        try container.encode(scheduleValue, forKey: .scheduleValue)
        try container.encode(state, forKey: .state)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(providerThreadID, forKey: .providerThreadID)
        try container.encode(personaId, forKey: .personaId)
        try container.encode(runtimeMode, forKey: .runtimeMode)
        try container.encodeIfPresent(repoPath, forKey: .repoPath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastRun, forKey: .lastRun)
        try container.encodeIfPresent(nextRun, forKey: .nextRun)
        try container.encodeIfPresent(lastError, forKey: .lastError)
    }

    var externalDirectoryPath: String? {
        get { repoPath }
        set { repoPath = newValue }
    }
}
