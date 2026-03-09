import Foundation
import Testing
@testable import AgentHubBuildServer

struct BuildServerCLITests {
    @Test
    func parsesPrepareReleaseCommand() throws {
        let cli = BuildServerCLI(
            arguments: [],
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
                .json
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
            planRelease: { _ in makePlan() },
            output: { output = $0 }
        )

        try cli.run()

        #expect(output.contains("\"codexVersion\""))
        #expect(output.contains("\"resolvedReleaseTag\""))
        #expect(output.contains("\"appBundlePath\""))
    }
}

private func makePlan() -> AgentHubReleasePlan {
    let workingDirectory = URL(fileURLWithPath: "/tmp/codex-cli-work", isDirectory: true)
    let universalBinaryURL = workingDirectory.appendingPathComponent("universal/codex")
    return AgentHubReleasePlan(
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
        buildResult: XcodeBuildResult(
            appBundleURL: URL(fileURLWithPath: "/tmp/AgentHub.app", isDirectory: true),
            derivedDataURL: URL(fileURLWithPath: "/tmp/DerivedData", isDirectory: true)
        ),
        bundleInjectionResult: CodexBundleInjectionResult(
            appBundleURL: URL(fileURLWithPath: "/tmp/AgentHub.app", isDirectory: true),
            injectedBinaryURL: URL(fileURLWithPath: "/tmp/AgentHub.app/Contents/Resources/codex")
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
