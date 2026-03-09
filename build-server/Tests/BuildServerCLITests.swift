import Foundation
import Testing
@testable import AgentHubBuildServer

struct BuildServerCLITests {
    @Test
    func parsesPrepareReleaseCommand() throws {
        let cli = BuildServerCLI(
            arguments: [],
            prepareArtifacts: { _ in makeArtifactPreparation() },
            planRelease: { _ in makePlan() },
            output: { _ in }
        )

        let parsed = try cli.parse(
            arguments: [
                "prepare-release",
                "--agenthub-version", "1.4.2",
                "--build-number", "42",
                "--channel", "stable",
                "--force",
                "--dry-run-no-build",
                "--json",
            ]
        )

        #expect(
            parsed == .prepareRelease(
                AgentHubReleaseRequest(
                    currentAgentHubVersion: "1.4.2",
                    currentBuildNumber: 42,
                    releaseChannel: "stable",
                    force: true
                ),
                .json,
                true
            )
        )
    }

    @Test
    func rendersJsonSummaryFromPreparedPlan() throws {
        var output = ""
        let cli = BuildServerCLI(
            arguments: [
                "prepare-release",
                "--agenthub-version", "1.4.2",
                "--build-number", "42",
                "--channel", "stable",
                "--json",
            ],
            prepareArtifacts: { _ in makeArtifactPreparation() },
            planRelease: { _ in makePlan() },
            output: { output = $0 }
        )

        try cli.run()

        #expect(output.contains("\"codexVersion\""))
        #expect(output.contains("\"resolvedReleaseTag\""))
        #expect(output.contains("\"appBundlePath\""))
        #expect(output.contains("\"bundledComparison\""))
    }

    @Test
    func rendersJsonSummaryForDryRunWithoutBuildPaths() throws {
        var output = ""
        let cli = BuildServerCLI(
            arguments: [
                "prepare-release",
                "--agenthub-version", "1.4.2",
                "--build-number", "42",
                "--channel", "stable",
                "--dry-run-no-build",
                "--json",
            ],
            prepareArtifacts: { _ in makeArtifactPreparation() },
            planRelease: { _ in makePlan() },
            output: { output = $0 }
        )

        try cli.run()

        #expect(output.contains("\"status\" : \"prepared-no-build\""))
        #expect(output.contains("\"universalBinaryPath\""))
        #expect(output.contains("\"matchedLatestArtifact\" : \"arm64\""))
        #expect(output.contains("\"appBundlePath\"") == false)
        #expect(output.contains("\"injectedBinaryPath\"") == false)
    }

    @Test
    func printsUsageOnlyForCliErrors() {
        #expect(
            BuildServerCLI.shouldPrintUsage(
                for: BuildServerCLIError.usage("Missing required --channel")
            )
        )
        #expect(
            BuildServerCLI.shouldPrintUsage(
                for: BuildServerCLIError.invalidArgument("Unknown argument: --wat")
            )
        )
        #expect(
            BuildServerCLI.shouldPrintUsage(
                for: CodexArtifactFetcherError.upstreamFetchFailed("GitHub releases request failed with status 401")
            ) == false
        )
    }
}

private func makeArtifactPreparation() -> AgentHubArtifactPreparation {
    let workingDirectory = URL(fileURLWithPath: "/tmp/codex-cli-work", isDirectory: true)
    let universalBinaryURL = workingDirectory.appendingPathComponent("universal/codex")
    return AgentHubArtifactPreparation(
        jobID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        codexRelease: CodexArtifactDescriptor(
            version: "1.2.3",
            releaseTag: "v1.2.3",
            assets: []
        ),
        preparedArtifacts: PreparedCodexArtifacts(
            workingDirectory: workingDirectory,
            checksumFileURL: workingDirectory.appendingPathComponent("checksums.txt"),
            arm64BinaryURL: workingDirectory.appendingPathComponent("arm64/codex"),
            x64BinaryURL: workingDirectory.appendingPathComponent("x64/codex"),
            universalBinaryURL: universalBinaryURL
        ),
        bundledComparison: BundledCodexComparison(
            bundledBinaryPath: "/tmp/repo/AgentHub/Resources/codex/codex",
            bundledBinarySHA256: "aaaa",
            latestArm64SHA256: "aaaa",
            latestX64SHA256: "bbbb",
            latestUniversalSHA256: "cccc",
            matchedLatestArtifact: .arm64
        ),
        targetAgentHubVersion: "1.4.3",
        targetBuildNumber: 43,
        sparklePublishPlan: SparklePublishPlan(
            appArchiveName: "AgentHub-1.4.3.zip",
            appcastPath: "updates/stable/appcast.xml",
            releaseNotesPath: "updates/stable/release-notes-1.4.3.html",
            channel: "stable"
        ),
        steps: [
            "Resolve latest stable Codex release (ignore -alpha)",
            "Fetch Codex artifact 1.2.3",
        ]
    )
}

private func makePlan() -> AgentHubReleasePlan {
    let preparation = makeArtifactPreparation()
    return AgentHubReleasePlan(
        jobID: preparation.jobID,
        codexRelease: preparation.codexRelease,
        preparedArtifacts: preparation.preparedArtifacts,
        bundledComparison: preparation.bundledComparison,
        buildResult: XcodeBuildResult(
            appBundleURL: URL(fileURLWithPath: "/tmp/AgentHub.app", isDirectory: true),
            derivedDataURL: URL(fileURLWithPath: "/tmp/DerivedData", isDirectory: true)
        ),
        bundleInjectionResult: CodexBundleInjectionResult(
            appBundleURL: URL(fileURLWithPath: "/tmp/AgentHub.app", isDirectory: true),
            injectedBinaryURL: URL(fileURLWithPath: "/tmp/AgentHub.app/Contents/Resources/codex")
        ),
        targetAgentHubVersion: preparation.targetAgentHubVersion,
        targetBuildNumber: preparation.targetBuildNumber,
        sparklePublishPlan: preparation.sparklePublishPlan,
        steps: preparation.steps + [
            "Build unsigned AgentHub.app bundle",
            "Inject latest Codex binary into AgentHub.app resources",
        ]
    )
}
