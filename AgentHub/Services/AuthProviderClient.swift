import Foundation

struct AuthLoginChallenge: Equatable {
    var provider: AuthProvider
    var verificationURL: URL
    var userCode: String
    var expiresInMinutes: Int?
}

@MainActor
protocol AuthProviderClient {
    var provider: AuthProvider { get }
    var capabilities: ProviderCapabilities { get }

    func refreshStatus() throws -> AuthState
    func startLogin() async throws -> AuthLoginChallenge?
    func waitForLoginCompletion() async throws -> AuthState
    func cancelLogin()
}
