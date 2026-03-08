import Foundation

struct AuthLoginChallenge: Equatable {
    var verificationURL: URL
    var userCode: String
    var expiresInMinutes: Int?
}

@MainActor
protocol AuthProviderClient {
    func refreshStatus() throws -> AuthState
    func startLogin() async throws -> AuthLoginChallenge?
    func waitForLoginCompletion() async throws -> AuthState
    func cancelLogin()
}
