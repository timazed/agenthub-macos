import Foundation
import Testing
@testable import AgentHub

@MainActor
struct AuthViewModelTests {
    @Test
    func startupRefreshMarksAuthenticatedState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
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

private func makeAuthManager(
    paths: AppPaths,
    refreshedState: AuthState,
    challenge: AuthLoginChallenge? = AuthLoginChallenge(
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH",
        expiresInMinutes: 15
    ),
    loginDelayNanoseconds: UInt64 = 0
) -> AuthManager {
    AuthManager(
        store: AuthStore(paths: paths),
        providerClient: AuthViewModelStubProviderClient(
            refreshedState: refreshedState,
            challenge: challenge,
            loginDelayNanoseconds: loginDelayNanoseconds
        )
    )
}

private struct AuthViewModelStubProviderClient: AuthProviderClient {
    var refreshedState: AuthState
    var challenge: AuthLoginChallenge?
    var loginDelayNanoseconds: UInt64 = 0

    func refreshStatus() throws -> AuthState {
        refreshedState
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
