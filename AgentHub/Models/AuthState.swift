import Foundation

enum AuthenticationStatus: String, Codable, Hashable {
    case unknown
    case authenticated
    case unauthenticated
    case failed
}

struct AuthState: Codable, Hashable {
    var status: AuthenticationStatus
    var accountLabel: String?
    var lastValidatedAt: Date?
    var failureReason: String?
    var updatedAt: Date

    var isAuthenticated: Bool {
        status == .authenticated
    }

    static func `default`() -> AuthState {
        AuthState(
            status: .unknown,
            accountLabel: nil,
            lastValidatedAt: nil,
            failureReason: nil,
            updatedAt: Date()
        )
    }
}
