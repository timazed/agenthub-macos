import Foundation
import Testing
@testable import AgentHub

@MainActor
struct AuthViewModelTests {
    @Test
    func startupRefreshMarksAuthenticatedState() async throws {
        let viewModel = AuthViewModel(
            authManager: AuthViewModelStubManager(
                refreshedState: AuthState(
                    provider: .codex,
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            openURL: { _ in true }
        )

        await viewModel.performStartupCheckIfNeeded()

        #expect(viewModel.isAuthenticated)
        #expect(viewModel.authState.accountLabel == "user@example.com")
    }

    @Test
    func refreshStatusSurfacesUnauthenticatedState() async throws {
        let viewModel = AuthViewModel(
            authManager: AuthViewModelStubManager(
                capabilities: .available(authMethods: [.deviceCode]),
                refreshedState: AuthState(
                    provider: .codex,
                    status: .unauthenticated,
                    accountLabel: nil,
                    lastValidatedAt: nil,
                    failureReason: "Not logged in",
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()

        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.authState.status == .unauthenticated)
        #expect(viewModel.statusTitle == "Get started with Codex")
    }

    @Test
    func claudeAuthenticatedStateUnlocksAppWhenChatIsSupported() async throws {
        let viewModel = AuthViewModel(
            authManager: AuthViewModelStubManager(
                capabilities: .available(authMethods: [.externalSetup], supportsChat: true, supportsScheduledTasks: false),
                refreshedState: AuthState(
                    provider: .claude,
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(provider: .claude),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()

        #expect(viewModel.canUseApp)
        #expect(viewModel.statusTitle == "Claude is ready")
    }
}

private struct AuthViewModelStubManager: AuthManaging {
    var capabilities: ProviderCapabilities = .available(authMethods: [.deviceCode])
    var refreshedState: AuthState

    var currentProvider: AuthProvider { refreshedState.provider }
    var availableProviders: [AuthProvider] { [.codex, .claude] }

    func loadCachedState() throws -> AuthState {
        refreshedState
    }

    func refreshStatus() throws -> AuthState {
        refreshedState
    }

    func requireAuthenticated() throws {
        if !refreshedState.isAuthenticated {
            throw AuthManagerError.unauthenticated(refreshedState.failureReason)
        }
    }

    func selectProvider(_ provider: AuthProvider) throws -> AuthState {
        AuthState(
            provider: provider,
            status: refreshedState.status,
            accountLabel: refreshedState.accountLabel,
            lastValidatedAt: refreshedState.lastValidatedAt,
            failureReason: refreshedState.failureReason,
            updatedAt: refreshedState.updatedAt
        )
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        AuthLoginChallenge(
            provider: refreshedState.provider,
            verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: "ABCD-EFGH",
            expiresInMinutes: 15
        )
    }

    func waitForLoginCompletion() async throws -> AuthState {
        refreshedState
    }

    func cancelLogin() {}
}
