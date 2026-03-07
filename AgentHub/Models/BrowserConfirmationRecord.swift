import Foundation

enum BrowserConfirmationResolution: String, Codable, Hashable {
    case pending
    case approved
    case rejected
    case takeOver
}

struct BrowserConfirmationRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var profileId: String
    var actionType: BrowserActionType
    var target: String?
    var currentURL: String?
    var pageTitle: String
    var resolution: BrowserConfirmationResolution
    var createdAt: Date
    var resolvedAt: Date?
}
