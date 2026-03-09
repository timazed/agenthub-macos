import Foundation
import Testing
@testable import AgentHubBuildServer

struct ReleaseServiceTests {
    @Test
    func prepareReleaseBumpsPatchVersionAndPlansSparkleArtifacts() throws {
        let extractedArtifacts = CodexExtractedArtifacts(
            workingDirectory: URL(fileURLWithPath: "/tmp/codex-work", isDirectory: true),
            checksumFileURL: URL(fileURLWithPath: "/tmp/codex-work/checksums.txt"),
            arm64BinaryURL: URL(fileURLWithPath: "/tmp/codex-work/arm64/codex"),
            x64BinaryURL: URL(fileURLWithPath: "/tmp/codex-work/x64/codex")
        )
        let preparedArtifacts = PreparedCodexArtifacts(
            workingDirectory: extractedArtifacts.workingDirectory,
            checksumFileURL: extractedArtifacts.checksumFileURL,
            arm64BinaryURL: extractedArtifacts.arm64BinaryURL,
            x64BinaryURL: extractedArtifacts.x64BinaryURL,
            universalBinaryURL: URL(fileURLWithPath: "/tmp/codex-work/universal/codex")
        )
        let service = AgentHubReleaseService(
            artifactFetcher: CodexArtifactFetcher(
                configurationProvider: {
                    GitHubReleasesConfiguration(
                        owner: "openai",
                        repository: "codex",
                        apiBaseURL: URL(string: "https://api.github.com")!,
                        authToken: nil
                    )
                },
                releaseDataProvider: { _ in
                    try releaseFixtureJSON(
                        """
                        [
                          {
                            "tag_name": "v1.2.3",
                            "name": "v1.2.3",
                            "draft": false,
                            "prerelease": false,
                            "published_at": "2026-03-08T10:00:00Z",
                            "assets": [
                              {
                                "name": "codex-darwin-arm64.tar.gz",
                                "browser_download_url": "https://example.com/codex-darwin-arm64.tar.gz"
                              }
                            ]
                          }
                        ]
                        """
                    )
                }
            ),
            artifactDownloader: CodexArtifactDownloader(
                preparedReleaseProvider: { _ in extractedArtifacts },
                workingDirectoryProvider: { extractedArtifacts.workingDirectory },
                dataProvider: { _ in Data() },
                archiveExtractor: { _, _ in }
            ),
            universalBinaryBuilder: CodexUniversalBinaryBuilder(
                preparedArtifactsProvider: { _ in preparedArtifacts },
                processRunner: { _, _ in }
            )
        )
        let request = AgentHubReleaseRequest(
            currentAgentHubVersion: "1.0.0",
            currentBuildNumber: 41,
            releaseChannel: "dev",
            force: false
        )

        let plan = try service.prepareRelease(request: request)

        #expect(plan.codexRelease.version == "1.2.3")
        #expect(plan.codexRelease.releaseTag == "v1.2.3")
        #expect(plan.codexRelease.assets.count == 1)
        #expect(plan.preparedArtifacts.universalBinaryURL == preparedArtifacts.universalBinaryURL)
        #expect(plan.targetAgentHubVersion == "1.0.1")
        #expect(plan.targetBuildNumber == 42)
        #expect(plan.sparklePublishPlan.appcastPath == "updates/dev/appcast.xml")
    }

    @Test
    func controllerQueuesReleaseResponseFromWorker() throws {
        let extractedArtifacts = CodexExtractedArtifacts(
            workingDirectory: URL(fileURLWithPath: "/tmp/codex-work-2", isDirectory: true),
            checksumFileURL: URL(fileURLWithPath: "/tmp/codex-work-2/checksums.txt"),
            arm64BinaryURL: URL(fileURLWithPath: "/tmp/codex-work-2/arm64/codex"),
            x64BinaryURL: URL(fileURLWithPath: "/tmp/codex-work-2/x64/codex")
        )
        let preparedArtifacts = PreparedCodexArtifacts(
            workingDirectory: extractedArtifacts.workingDirectory,
            checksumFileURL: extractedArtifacts.checksumFileURL,
            arm64BinaryURL: extractedArtifacts.arm64BinaryURL,
            x64BinaryURL: extractedArtifacts.x64BinaryURL,
            universalBinaryURL: URL(fileURLWithPath: "/tmp/codex-work-2/universal/codex")
        )
        let controller = AgentHubReleaseController(
            worker: CodexReleaseWorker(
                releaseService: AgentHubReleaseService(
                    artifactFetcher: CodexArtifactFetcher(
                        configurationProvider: {
                            GitHubReleasesConfiguration(
                                owner: "openai",
                                repository: "codex",
                                apiBaseURL: URL(string: "https://api.github.com")!,
                                authToken: nil
                            )
                        },
                        releaseDataProvider: { _ in
                            try releaseFixtureJSON(
                                """
                                [
                                  {
                                    "tag_name": "v2.0.0",
                                    "name": "v2.0.0",
                                    "draft": false,
                                    "prerelease": false,
                                    "published_at": "2026-03-08T11:00:00Z",
                                    "assets": [
                                      {
                                        "name": "codex-darwin-arm64.tar.gz",
                                        "browser_download_url": "https://example.com/codex-darwin-arm64.tar.gz"
                                      }
                                    ]
                                  }
                                ]
                                """
                            )
                        }
                    ),
                    artifactDownloader: CodexArtifactDownloader(
                        preparedReleaseProvider: { _ in extractedArtifacts },
                        workingDirectoryProvider: { extractedArtifacts.workingDirectory },
                        dataProvider: { _ in Data() },
                        archiveExtractor: { _, _ in }
                    ),
                    universalBinaryBuilder: CodexUniversalBinaryBuilder(
                        preparedArtifactsProvider: { _ in preparedArtifacts },
                        processRunner: { _, _ in }
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
        #expect(preparedArtifacts.universalBinaryURL.path.contains("universal"))
    }
}

private func releaseFixtureJSON(_ json: String) throws -> Data {
    guard let data = json.data(using: .utf8) else {
        throw TestFixtureError.invalidUTF8
    }
    return data
}

private enum TestFixtureError: Error {
    case invalidUTF8
}
