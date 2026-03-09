import Foundation

struct AgentHubReleasePlan: Equatable, Sendable {
    var jobID: UUID
    var codexArtifact: CodexArtifactDescriptor
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
        request: AgentHubReleaseRequest,
        currentBuildNumber: Int = 1
    ) -> AgentHubReleasePlan {
        let artifact = artifactFetcher.describe(request: request)
        let targetVersion = versioning.nextVersion(from: request.currentAgentHubVersion, for: request.codexVersion)
        let publishPlan = sparklePublisher.planPublish(agentHubVersion: targetVersion, channel: request.releaseChannel)

        return AgentHubReleasePlan(
            jobID: UUID(),
            codexArtifact: artifact,
            targetAgentHubVersion: targetVersion,
            targetBuildNumber: versioning.nextBuildNumber(from: currentBuildNumber),
            sparklePublishPlan: publishPlan,
            steps: [
                "Fetch Codex artifact \(artifact.version)",
                "Verify SHA256 checksum",
                "Replace bundled codex binary in AgentHub.app resources",
                "Bump AgentHub version to \(targetVersion)",
                "Build, sign, and notarize AgentHub",
                "Run generate_appcast for channel \(request.releaseChannel)",
            ]
        )
    }
}
