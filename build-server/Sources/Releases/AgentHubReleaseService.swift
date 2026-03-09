import Foundation

struct AgentHubReleasePlan: Equatable, Sendable {
    var jobID: UUID
    var codexRelease: CodexArtifactDescriptor
    var targetAgentHubVersion: String
    var targetBuildNumber: Int
    var sparklePublishPlan: SparklePublishPlan
    var steps: [String]
}

struct AgentHubReleaseService {
    var artifactFetcher = CodexArtifactFetcher()
    var versioning = AgentHubVersioning()
    var sparklePublisher = SparklePublishService()

    func prepareRelease(
        request: AgentHubReleaseRequest
    ) -> AgentHubReleasePlan {
        let release = artifactFetcher.resolveLatestStableRelease()
        let targetVersion = versioning.nextVersion(from: request.currentAgentHubVersion, for: release.version)
        let publishPlan = sparklePublisher.planPublish(agentHubVersion: targetVersion, channel: request.releaseChannel)

        return AgentHubReleasePlan(
            jobID: UUID(),
            codexRelease: release,
            targetAgentHubVersion: targetVersion,
            targetBuildNumber: versioning.nextBuildNumber(from: request.currentBuildNumber),
            sparklePublishPlan: publishPlan,
            steps: [
                "Resolve latest stable Codex release (ignore -alpha)",
                "Fetch Codex artifact \(release.version)",
                "Verify artifact checksums",
                "Replace bundled codex binary in AgentHub.app resources",
                "Bump AgentHub version to \(targetVersion)",
                "Build, sign, and notarize AgentHub",
                "Run generate_appcast for channel \(request.releaseChannel)",
            ]
        )
    }
}
