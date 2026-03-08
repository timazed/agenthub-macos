import Foundation

@MainActor
protocol AuthManaging {
    func loadCachedState() throws -> AuthState
    @discardableResult
    func refreshStatus() throws -> AuthState
    func requireAuthenticated() throws
    func startLogin() async throws -> AuthLoginChallenge?
    func waitForLoginCompletion() async throws -> AuthState
    func cancelLogin()
}
