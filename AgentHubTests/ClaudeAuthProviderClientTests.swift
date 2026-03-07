import Foundation
import Testing
@testable import AgentHub

struct ClaudeAuthProviderClientTests {
    @Test
    func capabilitiesExposeChatOnlySupport() {
        let client = ClaudeAuthProviderClient(paths: AppPaths(root: FileManager.default.temporaryDirectory))

        #expect(client.capabilities.supportsChat)
        #expect(!client.capabilities.supportsScheduledTasks)
        #expect(client.capabilities.authMethods == [.externalSetup])
    }
}
