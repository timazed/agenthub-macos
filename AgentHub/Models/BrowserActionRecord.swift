import Foundation

enum BrowserActionResultStatus: String, Codable, Hashable {
    case pending
    case succeeded
    case blocked
    case failed
}

struct BrowserActionRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionId: UUID
    var profileId: String
    var currentURL: String?
    var actionType: BrowserActionType
    var target: String?
    var value: String?
    var result: BrowserActionResultStatus
    var error: String?
    var createdAt: Date
}
