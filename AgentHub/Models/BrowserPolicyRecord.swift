import Foundation

enum BrowserActionType: String, Codable, Hashable, CaseIterable {
    case open
    case goBack
    case goForward
    case reload
    case click
    case fill
    case select
    case submit
    case scroll
}

struct BrowserConfirmationRule: Codable, Hashable {
    var actionType: BrowserActionType
    var hostPattern: String?
    var notes: String?
}

struct BrowserPolicyRecord: Identifiable, Codable, Hashable {
    var id: String { profileId }
    var profileId: String
    var displayName: String
    var allowedHosts: [String]
    var confirmationRules: [BrowserConfirmationRule]
    var notes: String?

    static func `default`(profileId: String = "default", displayName: String = "Default Browser") -> BrowserPolicyRecord {
        BrowserPolicyRecord(
            profileId: profileId,
            displayName: displayName,
            allowedHosts: [],
            confirmationRules: [
                BrowserConfirmationRule(actionType: .submit, hostPattern: nil, notes: "Require approval before final submission.")
            ],
            notes: nil
        )
    }
}
