import Foundation
import Testing
@testable import AgentHubBuildServer

struct ReleaseServiceTests {
    @Test
    func prepareReleaseBumpsPatchVersionAndPlansSparkleArtifacts() {
        let service = AgentHubReleaseService()
        let request = AgentHubReleaseRequest(
            codexVersion: "1.2.3",
            codexArtifactURL: URL(string: "https://example.com/codex-1.2.3.tar.gz")!,
            codexSHA256: "abc123",
            currentAgentHubVersion: "1.0.0",
            releaseChannel: "dev",
            force: false
        )

        let plan = service.prepareRelease(request: request, currentBuildNumber: 41)

        #expect(plan.codexArtifact.version == "1.2.3")
        #expect(plan.targetAgentHubVersion == "1.0.1")
        #expect(plan.targetBuildNumber == 42)
        #expect(plan.sparklePublishPlan.appcastPath == "updates/dev/appcast.xml")
    }

    @Test
    func controllerQueuesReleaseResponseFromWorker() throws {
        let controller = AgentHubReleaseController(
            worker: CodexReleaseWorker(releaseService: AgentHubReleaseService())
        )
        let request = AgentHubReleaseRequest(
            codexVersion: "2.0.0",
            codexArtifactURL: URL(string: "https://example.com/codex-2.0.0.tar.gz")!,
            codexSHA256: "def456",
            currentAgentHubVersion: "1.4.2",
            releaseChannel: "stable",
            force: true
        )

        let response = try controller.enqueueRelease(request)

        #expect(response.status == "queued")
        #expect(response.codexVersion == "2.0.0")
        #expect(response.targetAgentHubVersion == "1.4.3")
        #expect(response.notes.isEmpty == false)
    }
}
