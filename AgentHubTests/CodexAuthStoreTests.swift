import Foundation
import Testing
@testable import AgentHub

struct CodexAuthStoreTests {
    @Test
    func loadOrCreateDefaultPersistsUnknownState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = AuthStore(paths: paths)

        let state = try store.loadOrCreateDefault()

        #expect(state.status == .unknown)
        #expect(state.accountLabel == nil)
        #expect(state.lastValidatedAt == nil)
        #expect(state.failureReason == nil)
        #expect(FileManager.default.fileExists(atPath: paths.codexAuthStateURL.path))
    }

    @Test
    func saveRoundTripsAuthenticationMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = AuthStore(paths: paths)
        let now = Date(timeIntervalSince1970: 1_700_000_123)
        let state = AuthState(
            status: .authenticated,
            accountLabel: "user@example.com",
            lastValidatedAt: now,
            failureReason: nil,
            updatedAt: now
        )

        try store.save(state)
        let loaded = try store.load()

        #expect(loaded == state)
        #expect(loaded.isAuthenticated)
    }
}
