import CryptoKit
import Foundation

enum BundledCodexMatchKind: String, Codable, Equatable, Sendable {
    case arm64
    case x64
    case universal
    case none
}

struct BundledCodexComparison: Codable, Equatable, Sendable {
    var bundledBinaryPath: String
    var bundledBinarySHA256: String
    var latestArm64SHA256: String
    var latestX64SHA256: String
    var latestUniversalSHA256: String
    var matchedLatestArtifact: BundledCodexMatchKind
}

struct AgentHubArtifactPreparation: Equatable, Sendable {
    var jobID: UUID
    var codexRelease: CodexArtifactDescriptor
    var preparedArtifacts: PreparedCodexArtifacts
    var bundledComparison: BundledCodexComparison?
    var targetAgentHubVersion: String
    var targetBuildNumber: Int
    var sparklePublishPlan: SparklePublishPlan
    var steps: [String]
}

struct AgentHubReleasePlan: Equatable, Sendable {
    var jobID: UUID
    var codexRelease: CodexArtifactDescriptor
    var preparedArtifacts: PreparedCodexArtifacts
    var bundledComparison: BundledCodexComparison?
    var buildResult: XcodeBuildResult
    var bundleInjectionResult: CodexBundleInjectionResult
    var targetAgentHubVersion: String
    var targetBuildNumber: Int
    var sparklePublishPlan: SparklePublishPlan
    var steps: [String]
}

struct AgentHubReleaseService {
    var fileManager: FileManager = .default
    var artifactFetcher = CodexArtifactFetcher()
    var artifactDownloader = CodexArtifactDownloader()
    var universalBinaryBuilder = CodexUniversalBinaryBuilder()
    var bundleInjector = CodexBundleInjector()
    var xcodeArchiveService = XcodeArchiveService()
    var versioning = AgentHubVersioning()
    var sparklePublisher = SparklePublishService()
    var bundledBinaryURLProvider: @Sendable () -> URL = {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("AgentHub", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)
    }
    var bundledBinaryExistsProvider: @Sendable (URL) -> Bool = { fileURL in
        FileManager.default.fileExists(atPath: fileURL.path)
    }
    var sha256Provider: @Sendable (URL) throws -> String = { fileURL in
        try AgentHubReleaseService.sha256(for: fileURL)
    }

    func prepareArtifacts(
        request: AgentHubReleaseRequest
    ) throws -> AgentHubArtifactPreparation {
        let release = try artifactFetcher.resolveLatestStableRelease()
        let extractedArtifacts = try artifactDownloader.prepareRelease(release)
        let preparedArtifacts = try universalBinaryBuilder.buildUniversalBinary(from: extractedArtifacts)
        let bundledComparison = try compareBundledBinary(against: preparedArtifacts)
        let targetVersion = versioning.nextVersion(from: request.currentAgentHubVersion, for: release.version)
        let publishPlan = sparklePublisher.planPublish(agentHubVersion: targetVersion, channel: request.releaseChannel)
        let comparisonStep = bundledComparison == nil
            ? "Skip bundled Codex comparison because the repo fallback binary was not found"
            : "Compare repo-bundled Codex binary against latest staged artifacts"

        return AgentHubArtifactPreparation(
            jobID: UUID(),
            codexRelease: release,
            preparedArtifacts: preparedArtifacts,
            bundledComparison: bundledComparison,
            targetAgentHubVersion: targetVersion,
            targetBuildNumber: versioning.nextBuildNumber(from: request.currentBuildNumber),
            sparklePublishPlan: publishPlan,
            steps: [
                "Resolve latest stable Codex release (ignore -alpha)",
                "Fetch Codex artifact \(release.version)",
                "Verify artifact checksums",
                "Assemble universal macOS Codex binary",
                comparisonStep,
                "Prepare Sparkle publish plan for channel \(request.releaseChannel)",
            ]
        )
    }

    func prepareRelease(
        request: AgentHubReleaseRequest
    ) throws -> AgentHubReleasePlan {
        let artifactPreparation = try prepareArtifacts(request: request)
        let buildResult = try xcodeArchiveService.buildUnsignedApp()
        let bundleInjectionResult = try bundleInjector.inject(
            universalBinaryURL: artifactPreparation.preparedArtifacts.universalBinaryURL,
            intoAppBundle: buildResult.appBundleURL
        )

        return AgentHubReleasePlan(
            jobID: artifactPreparation.jobID,
            codexRelease: artifactPreparation.codexRelease,
            preparedArtifacts: artifactPreparation.preparedArtifacts,
            bundledComparison: artifactPreparation.bundledComparison,
            buildResult: buildResult,
            bundleInjectionResult: bundleInjectionResult,
            targetAgentHubVersion: artifactPreparation.targetAgentHubVersion,
            targetBuildNumber: artifactPreparation.targetBuildNumber,
            sparklePublishPlan: artifactPreparation.sparklePublishPlan,
            steps: artifactPreparation.steps + [
                "Build unsigned AgentHub.app bundle",
                "Inject latest Codex binary into AgentHub.app resources",
                "Build, sign, and notarize AgentHub",
                "Run generate_appcast for channel \(request.releaseChannel)",
            ]
        )
    }

    private func compareBundledBinary(
        against preparedArtifacts: PreparedCodexArtifacts
    ) throws -> BundledCodexComparison? {
        let bundledBinaryURL = bundledBinaryURLProvider()
        guard bundledBinaryExistsProvider(bundledBinaryURL) else {
            return nil
        }

        let bundledBinarySHA256 = try sha256Provider(bundledBinaryURL)
        let latestArm64SHA256 = try sha256Provider(preparedArtifacts.arm64BinaryURL)
        let latestX64SHA256 = try sha256Provider(preparedArtifacts.x64BinaryURL)
        let latestUniversalSHA256 = try sha256Provider(preparedArtifacts.universalBinaryURL)
        let matchedLatestArtifact: BundledCodexMatchKind

        if bundledBinarySHA256 == latestArm64SHA256 {
            matchedLatestArtifact = .arm64
        } else if bundledBinarySHA256 == latestX64SHA256 {
            matchedLatestArtifact = .x64
        } else if bundledBinarySHA256 == latestUniversalSHA256 {
            matchedLatestArtifact = .universal
        } else {
            matchedLatestArtifact = .none
        }

        return BundledCodexComparison(
            bundledBinaryPath: bundledBinaryURL.path,
            bundledBinarySHA256: bundledBinarySHA256,
            latestArm64SHA256: latestArm64SHA256,
            latestX64SHA256: latestX64SHA256,
            latestUniversalSHA256: latestUniversalSHA256,
            matchedLatestArtifact: matchedLatestArtifact
        )
    }

    private static func sha256(for fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
        }

        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0, let streamError = stream.streamError {
                throw streamError
            }
            if readCount == 0 {
                break
            }

            hasher.update(data: Data(bytes: buffer, count: readCount))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
