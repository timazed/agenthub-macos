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
}

private struct AuthViewModelStubManager: AuthManaging {
    var refreshedState: AuthState

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

    func startLogin() async throws -> AuthLoginChallenge {
        AuthLoginChallenge(
            provider: .codex,
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
