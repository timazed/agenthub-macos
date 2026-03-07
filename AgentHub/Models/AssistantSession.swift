import Foundation

struct AssistantSession: Identifiable, Codable, Hashable {
    var id: UUID
    var provider: AuthProvider
    var providerThreadID: String?
    var personaId: String
    var mode: RuntimeMode
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        provider: AuthProvider,
        providerThreadID: String?,
        personaId: String,
        mode: RuntimeMode,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.providerThreadID = providerThreadID
        self.personaId = personaId
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
