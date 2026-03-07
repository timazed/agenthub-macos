import Foundation

enum AuthProvider: String, Codable, CaseIterable, Hashable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }
}
