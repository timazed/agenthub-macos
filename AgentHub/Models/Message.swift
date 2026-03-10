import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessageSource: String, Codable, Hashable {
    case userInput
    case codexStdout
    case codexStderr
    case taskSystemEvent
    case iMessageIncoming
    case iMessageOutgoing
}

struct Message: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var role: MessageRole
    var text: String
    var source: MessageSource
    var createdAt: Date
}
