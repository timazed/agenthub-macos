import Foundation

enum AuthProvider: String, Codable, Hashable {
    case codex

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        }
    }
}
