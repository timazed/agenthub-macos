import Foundation

struct BrowserSessionRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var profileId: String
    var currentURL: String?
    var title: String
    var isLoading: Bool
    var startedAt: Date
}
