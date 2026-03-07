import Foundation

struct BrowserPageSnapshot: Identifiable, Codable, Hashable {
    var id: String
    var sessionId: UUID
    var currentURL: String?
    var title: String
    var isLoading: Bool
    var visibleTextSummary: String
    var actionableElements: [BrowserActionableElement]
    var createdAt: Date
}
