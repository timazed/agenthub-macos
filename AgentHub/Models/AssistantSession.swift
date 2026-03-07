import Foundation

struct AssistantSession: Identifiable, Codable, Hashable {
    var id: UUID
    var provider: AuthProvider
    var providerThreadID: String?
    var personaId: String
    var mode: RuntimeMode
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case providerThreadID
        case codexThreadId
        case personaId
        case mode
        case createdAt
        case updatedAt
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decodeIfPresent(AuthProvider.self, forKey: .provider) ?? .codex
        let providerThread = try container.decodeIfPresent(String.self, forKey: .providerThreadID)
        let legacyThread = try container.decodeIfPresent(String.self, forKey: .codexThreadId)
        providerThreadID = providerThread ?? legacyThread
        personaId = try container.decode(String.self, forKey: .personaId)
        mode = try container.decode(RuntimeMode.self, forKey: .mode)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(providerThreadID, forKey: .providerThreadID)
        try container.encode(personaId, forKey: .personaId)
        try container.encode(mode, forKey: .mode)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
