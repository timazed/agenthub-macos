import Foundation

enum CodexAuthenticationStatus: String, Codable, Hashable {
    case unknown
    case authenticated
    case unauthenticated
    case failed
}

struct CodexAuthState: Codable, Hashable {
    var status: CodexAuthenticationStatus
    var accountEmail: String?
    var lastValidatedAt: Date?
    var failureReason: String?
    var updatedAt: Date

    var isAuthenticated: Bool {
        status == .authenticated
    }

    static func `default`() -> CodexAuthState {
        CodexAuthState(
            status: .unknown,
            accountEmail: nil,
            lastValidatedAt: nil,
            failureReason: nil,
            updatedAt: Date()
        )
    }
}
