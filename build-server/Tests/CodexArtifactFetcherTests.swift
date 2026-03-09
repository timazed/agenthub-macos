import Foundation
import Testing
@testable import AgentHubBuildServer

struct CodexArtifactFetcherTests {
    @Test
    func selectsLatestStableReleaseAndIgnoresAlphaCandidates() throws {
        let fetcher = CodexArtifactFetcher(
            configurationProvider: {
                GitHubReleasesConfiguration(
                    owner: "openai",
                    repository: "codex",
                    apiBaseURL: URL(string: "https://api.github.com")!,
                    authToken: nil
                )
            },
            releaseDataProvider: { _ in
                try fixtureData(
                    """
                    [
                      {
                        "tag_name": "v2.1.0-alpha.1",
                        "name": "v2.1.0-alpha.1",
                        "draft": false,
                        "prerelease": true,
                        "published_at": "2026-03-08T12:00:00Z",
                        "assets": [
                          {
                            "name": "codex-darwin-arm64-alpha.tar.gz",
                            "browser_download_url": "https://example.com/codex-darwin-arm64-alpha.tar.gz"
                          }
                        ]
                      },
                      {
                        "tag_name": "v2.0.1",
                        "name": "v2.0.1",
                        "draft": false,
                        "prerelease": false,
                        "published_at": "2026-03-08T11:00:00Z",
                        "assets": [
                          {
                            "name": "codex-darwin-arm64.tar.gz",
                            "browser_download_url": "https://example.com/codex-darwin-arm64.tar.gz"
                          },
                          {
                            "name": "checksums.txt",
                            "browser_download_url": "https://example.com/checksums.txt"
                          }
                        ]
                      }
                    ]
                    """
                )
            }
        )

        let release = try fetcher.resolveLatestStableRelease()

        #expect(release.version == "2.0.1")
        #expect(release.releaseTag == "v2.0.1")
        #expect(release.assets.count == 2)
        #expect(release.assets.contains { $0.kind == .darwinArm64 })
        #expect(release.assets.contains { $0.kind == .checksums })
    }

    @Test
    func rejectsStableReleaseWithoutUsableNonAlphaAssets() throws {
        let fetcher = CodexArtifactFetcher(
            configurationProvider: {
                GitHubReleasesConfiguration(
                    owner: "openai",
                    repository: "codex",
                    apiBaseURL: URL(string: "https://api.github.com")!,
                    authToken: nil
                )
            },
            releaseDataProvider: { _ in
                try fixtureData(
                    """
                    [
                      {
                        "tag_name": "v3.0.0",
                        "name": "v3.0.0",
                        "draft": false,
                        "prerelease": false,
                        "published_at": "2026-03-08T12:00:00Z",
                        "assets": [
                          {
                            "name": "codex-darwin-arm64-alpha.tar.gz",
                            "browser_download_url": "https://example.com/codex-darwin-arm64-alpha.tar.gz"
                          }
                        ]
                      }
                    ]
                    """
                )
            }
        )

        #expect(throws: CodexArtifactFetcherError.self) {
            try fetcher.resolveLatestStableRelease()
        }
    }

    @Test
    func classifiesDarwinArchitecturesFromAssetNames() {
        let fetcher = CodexArtifactFetcher()

        #expect(fetcher.assetKind(for: "codex-darwin-arm64.tar.gz") == .darwinArm64)
        #expect(fetcher.assetKind(for: "codex-apple-darwin-x86_64.tar.gz") == .darwinX64)
        #expect(fetcher.assetKind(for: "checksums.txt") == .checksums)
        #expect(fetcher.assetKind(for: "codex-linux-x86_64.tar.gz") == .other)
    }

    @Test
    func formatsUnauthorizedMessageWhenAuthTokenWasProvided() {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/openai/codex/releases")!)
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")

        let message = GitHubReleasesHTTPErrorFormatter.message(statusCode: 401, request: request)

        #expect(message.contains("GITHUB_TOKEN"))
        #expect(message.contains("configured repository"))
    }

    @Test
    func formatsUnauthorizedMessageWhenNoAuthTokenWasProvided() {
        let request = URLRequest(url: URL(string: "https://api.github.com/repos/openai/codex/releases")!)

        let message = GitHubReleasesHTTPErrorFormatter.message(statusCode: 401, request: request)

        #expect(message.contains("Set GITHUB_TOKEN"))
        #expect(message.contains("private"))
    }
}

private func fixtureData(_ json: String) throws -> Data {
    guard let data = json.data(using: .utf8) else {
        throw FixtureError.invalidUTF8
    }
    return data
}

private enum FixtureError: Error {
    case invalidUTF8
}
