import Foundation

struct TaskRunRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var taskId: UUID
    var codexThreadId: String?
    var startedAt: Date
    var finishedAt: Date?
    var exitCode: Int32?
    var stdout: String
    var stderr: String
}
