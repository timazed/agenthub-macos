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
}
