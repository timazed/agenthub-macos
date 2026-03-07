import Foundation

protocol AuthManaging {
    var currentProvider: AuthProvider { get }
    var availableProviders: [AuthProvider] { get }
    var capabilities: ProviderCapabilities { get }

    func loadCachedState() throws -> AuthState
    @discardableResult
    func refreshStatus() throws -> AuthState
    func requireAuthenticated() throws
    @discardableResult
    func selectProvider(_ provider: AuthProvider) throws -> AuthState
    func startLogin() async throws -> AuthLoginChallenge?
    func waitForLoginCompletion() async throws -> AuthState
    func cancelLogin()
}
