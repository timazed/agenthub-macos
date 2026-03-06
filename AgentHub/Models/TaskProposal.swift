import Foundation

struct TaskProposal: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var instructions: String
    var scheduleType: TaskScheduleType
    var scheduleValue: String
    var runtimeMode: RuntimeMode
    var repoPath: String?
    var runNow: Bool

    var externalDirectoryPath: String? {
        get { repoPath }
        set { repoPath = newValue }
    }
}
