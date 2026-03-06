import Foundation

enum ActivityKind: String, Codable, CaseIterable {
    case taskCreated
    case taskUpdated
    case taskScheduled
    case taskRunStarted
    case taskRunCompleted
    case taskRunFailed
    case taskPaused
    case taskCompleted
    case taskNeedsInput
    case assistantAction
}

struct ActivityEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var taskId: UUID?
    var kind: ActivityKind
    var message: String
    var createdAt: Date
}
