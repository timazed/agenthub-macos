import Foundation

struct AssistantSession: Identifiable, Codable, Hashable {
    var id: UUID
    var codexThreadId: String?
    var personaId: String
    var mode: RuntimeMode
    var createdAt: Date
    var updatedAt: Date
}
