import Foundation
import Testing
@testable import AgentHub

struct AuthManagerTests {
    @Test
    func refreshStatusPersistsAuthenticatedState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = AuthStore(paths: paths)
        let manager = AuthManager(
            store: store,
            providerClient: StubAuthProviderClient(
                refreshedState: AuthState(
                    provider: .codex,
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_200),
                    failureReason: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
                )
            )
        )

        let state = try manager.refreshStatus()

        #expect(state.status == .authenticated)
        #expect(state.accountLabel == "user@example.com")
        #expect((try? store.load()) == state)
    }

    @Test
    func requireAuthenticatedThrowsForLoggedOutState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = AuthStore(paths: paths)
        let manager = AuthManager(
            store: store,
            providerClient: StubAuthProviderClient(
                refreshedState: AuthState(
                    provider: .codex,
                    status: .unauthenticated,
                    accountLabel: nil,
                    lastValidatedAt: nil,
                    failureReason: "Not logged in",
                    updatedAt: Date()
                )
            )
        )

        #expect(throws: AuthManagerError.self) {
            try manager.requireAuthenticated()
        }

        let cached = try store.loadOrCreateDefault()
        #expect(cached.status == .unauthenticated)
        #expect(cached.failureReason == "Not logged in")
    }
}

private struct StubAuthProviderClient: AuthProviderClient {
    let provider: AuthProvider = .codex
    let capabilities = ProviderCapabilities.available(authMethods: [.browser])
    var refreshedState: AuthState
    var challenge: AuthLoginChallenge = AuthLoginChallenge(
        provider: .codex,
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH",
        expiresInMinutes: 15
    )

    func refreshStatus() throws -> AuthState {
        refreshedState
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        challenge
    }

    func waitForLoginCompletion() async throws -> AuthState {
        refreshedState
    }

    func cancelLogin() {}
}
