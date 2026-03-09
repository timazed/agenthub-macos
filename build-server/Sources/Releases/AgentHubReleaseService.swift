import Foundation

struct AgentHubReleasePlan: Equatable, Sendable {
    var jobID: UUID
    var codexRelease: CodexArtifactDescriptor
    var preparedArtifacts: PreparedCodexArtifacts
    var buildResult: XcodeBuildResult
    var bundleInjectionResult: CodexBundleInjectionResult
    var targetAgentHubVersion: String
    var targetBuildNumber: Int
    var sparklePublishPlan: SparklePublishPlan
    var steps: [String]
}

struct AgentHubReleaseService {
    var artifactFetcher = CodexArtifactFetcher()
    var artifactDownloader = CodexArtifactDownloader()
    var universalBinaryBuilder = CodexUniversalBinaryBuilder()
    var bundleInjector = CodexBundleInjector()
    var xcodeArchiveService = XcodeArchiveService()
    var versioning = AgentHubVersioning()
    var sparklePublisher = SparklePublishService()

    func prepareRelease(
        request: AgentHubReleaseRequest
    ) throws -> AgentHubReleasePlan {
        let release = try artifactFetcher.resolveLatestStableRelease()
        let extractedArtifacts = try artifactDownloader.prepareRelease(release)
        let preparedArtifacts = try universalBinaryBuilder.buildUniversalBinary(from: extractedArtifacts)
        let buildResult = try xcodeArchiveService.buildUnsignedApp()
        let bundleInjectionResult = try bundleInjector.inject(
            universalBinaryURL: preparedArtifacts.universalBinaryURL,
            intoAppBundle: buildResult.appBundleURL
        )
        let targetVersion = versioning.nextVersion(from: request.currentAgentHubVersion, for: release.version)
        let publishPlan = sparklePublisher.planPublish(agentHubVersion: targetVersion, channel: request.releaseChannel)

        return AgentHubReleasePlan(
            jobID: UUID(),
            codexRelease: release,
            preparedArtifacts: preparedArtifacts,
            buildResult: buildResult,
            bundleInjectionResult: bundleInjectionResult,
            targetAgentHubVersion: targetVersion,
            targetBuildNumber: versioning.nextBuildNumber(from: request.currentBuildNumber),
            sparklePublishPlan: publishPlan,
            steps: [
                "Resolve latest stable Codex release (ignore -alpha)",
                "Fetch Codex artifact \(release.version)",
                "Verify artifact checksums",
                "Assemble universal macOS Codex binary",
                "Build unsigned AgentHub.app bundle",
                "Inject latest Codex binary into AgentHub.app resources",
                "Bump AgentHub version to \(targetVersion)",
                "Build, sign, and notarize AgentHub",
                "Run generate_appcast for channel \(request.releaseChannel)",
            ]
        )
    }
}
