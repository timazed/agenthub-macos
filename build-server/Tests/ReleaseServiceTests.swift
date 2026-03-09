import Foundation
import Testing
@testable import AgentHubBuildServer

struct ReleaseServiceTests {
    @Test
    func prepareReleaseBumpsPatchVersionAndPlansSparkleArtifacts() {
        let service = AgentHubReleaseService(
            artifactFetcher: CodexArtifactFetcher(
                latestStableReleaseProvider: {
                    CodexArtifactDescriptor(version: "1.2.3", releaseTag: "v1.2.3")
                }
            )
        )
        let request = AgentHubReleaseRequest(
            currentAgentHubVersion: "1.0.0",
            currentBuildNumber: 41,
            releaseChannel: "dev",
            force: false
        )

        let plan = service.prepareRelease(request: request)

        #expect(plan.codexRelease.version == "1.2.3")
        #expect(plan.codexRelease.releaseTag == "v1.2.3")
        #expect(plan.targetAgentHubVersion == "1.0.1")
        #expect(plan.targetBuildNumber == 42)
        #expect(plan.sparklePublishPlan.appcastPath == "updates/dev/appcast.xml")
    }

    @Test
    func controllerQueuesReleaseResponseFromWorker() throws {
        let controller = AgentHubReleaseController(
            worker: CodexReleaseWorker(
                releaseService: AgentHubReleaseService(
                    artifactFetcher: CodexArtifactFetcher(
                        latestStableReleaseProvider: {
                            CodexArtifactDescriptor(version: "2.0.0", releaseTag: "v2.0.0")
                        }
                    )
                )
            )
        )
        let request = AgentHubReleaseRequest(
            currentAgentHubVersion: "1.4.2",
            currentBuildNumber: 9,
            releaseChannel: "stable",
            force: true
        )

        let response = try controller.enqueueRelease(request)

        #expect(response.status == "queued")
        #expect(response.codexVersion == "2.0.0")
        #expect(response.resolvedReleaseTag == "v2.0.0")
        #expect(response.targetAgentHubVersion == "1.4.3")
        #expect(response.targetBuildNumber == 10)
        #expect(response.notes.isEmpty == false)
    }
}
