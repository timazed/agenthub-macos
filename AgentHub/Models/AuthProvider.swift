import Foundation

enum AuthProvider: String, Codable, Hashable {
    case codex

    var displayName: String {
        "Codex"
    }
}
