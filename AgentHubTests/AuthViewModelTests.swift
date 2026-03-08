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

    @Test
    func beginLoginWithoutChallengeShowsBrowserWaitingState() async throws {
        let viewModel = AuthViewModel(
            authManager: AuthViewModelStubManager(
                refreshedState: AuthState(
                    provider: .codex,
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                ),
                challenge: nil,
                loginDelayNanoseconds: 50_000_000
            ),
            initialState: .default(),
            openURL: { _ in
                Issue.record("Browser login without a challenge should not request an app-managed URL open.")
                return true
            }
        )

        let task = Task {
            await viewModel.beginLogin()
        }

        await Task.yield()

        #expect(viewModel.isAwaitingBrowserCompletion)
        #expect(viewModel.showsBrowserWaitingCard)
        #expect(viewModel.statusMessage.contains("Finish signing in in your browser"))

        await task.value

        #expect(viewModel.authState.status == .authenticated)
        #expect(!viewModel.isAwaitingBrowserCompletion)
    }
}

private struct AuthViewModelStubManager: AuthManaging {
    var refreshedState: AuthState
    var challenge: AuthLoginChallenge? = AuthLoginChallenge(
        provider: .codex,
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH",
        expiresInMinutes: 15
    )
    var loginDelayNanoseconds: UInt64 = 0

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

    func startLogin() async throws -> AuthLoginChallenge? {
        challenge
    }

    func waitForLoginCompletion() async throws -> AuthState {
        if loginDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: loginDelayNanoseconds)
        }
        return refreshedState
    }

    func cancelLogin() {}
}
