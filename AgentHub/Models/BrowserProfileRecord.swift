import Foundation

enum BrowserToolingKind: String, Codable, Hashable, CaseIterable {
    case generic
}

enum BrowserStorageScope: String, Codable, Hashable, CaseIterable {
    case sharedDefault
}

struct BrowserProfileRecord: Identifiable, Codable, Hashable {
    var id: String { profileId }
    var profileId: String
    var displayName: String
    var notes: String?
    var toolingKind: BrowserToolingKind
    var storageScope: BrowserStorageScope

    static func `default`() -> BrowserProfileRecord {
        BrowserProfileRecord(
            profileId: "default",
            displayName: "Default Browser",
            notes: nil,
            toolingKind: .generic,
            storageScope: .sharedDefault
        )
    }
}
