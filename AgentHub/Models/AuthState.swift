import Foundation

enum AuthenticationStatus: String, Codable, Hashable {
    case unknown
    case authenticated
    case unauthenticated
    case failed
}

struct AuthState: Codable, Hashable {
    var provider: AuthProvider
    var status: AuthenticationStatus
    var accountLabel: String?
    var lastValidatedAt: Date?
    var failureReason: String?
    var updatedAt: Date

    var isAuthenticated: Bool {
        status == .authenticated
    }

    static func `default`(provider: AuthProvider = .codex) -> AuthState {
        AuthState(
            provider: provider,
            status: .unknown,
            accountLabel: nil,
            lastValidatedAt: nil,
            failureReason: nil,
            updatedAt: Date()
        )
    }
}
