import Foundation

struct TaskRunRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var taskId: UUID
    var providerThreadID: String?
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    var stdout: String
    var stderr: String

    private enum CodingKeys: String, CodingKey {
        case id
        case taskId
        case providerThreadID
        case codexThreadId
        case startedAt
        case finishedAt
        case exitCode
        case stdout
        case stderr
    }

    init(
        id: UUID,
        taskId: UUID,
        providerThreadID: String?,
        startedAt: Date,
        finishedAt: Date?,
        exitCode: Int32?,
        stdout: String,
        stderr: String
    ) {
        self.id = id
        self.taskId = taskId
        self.providerThreadID = providerThreadID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskId = try container.decode(UUID.self, forKey: .taskId)
        let providerThread = try container.decodeIfPresent(String.self, forKey: .providerThreadID)
        let legacyThread = try container.decodeIfPresent(String.self, forKey: .codexThreadId)
        providerThreadID = providerThread ?? legacyThread
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        stdout = try container.decode(String.self, forKey: .stdout)
        stderr = try container.decode(String.self, forKey: .stderr)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(taskId, forKey: .taskId)
        try container.encodeIfPresent(providerThreadID, forKey: .providerThreadID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        try container.encode(stdout, forKey: .stdout)
        try container.encode(stderr, forKey: .stderr)
    }
}
