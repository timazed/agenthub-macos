import Foundation

struct GitHubReleasesConfiguration: Equatable, Sendable {
    var owner: String
    var repository: String
    var apiBaseURL: URL
    var authToken: String?

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> GitHubReleasesConfiguration {
        guard let owner = environment["CODEX_GITHUB_OWNER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              owner.isEmpty == false,
              let repository = environment["CODEX_GITHUB_REPO"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              repository.isEmpty == false else {
            throw CodexArtifactFetcherError.invalidConfiguration(
                "Missing CODEX_GITHUB_OWNER or CODEX_GITHUB_REPO"
            )
        }

        let apiBaseURL: URL
        if let rawAPIBaseURL = environment["CODEX_GITHUB_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           rawAPIBaseURL.isEmpty == false {
            guard let parsedURL = URL(string: rawAPIBaseURL) else {
                throw CodexArtifactFetcherError.invalidConfiguration(
                    "Invalid CODEX_GITHUB_API_BASE_URL"
                )
            }
            apiBaseURL = parsedURL
        } else {
            apiBaseURL = URL(string: "https://api.github.com")!
        }

        let authToken = environment["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return GitHubReleasesConfiguration(
            owner: owner,
            repository: repository,
            apiBaseURL: apiBaseURL,
            authToken: authToken?.isEmpty == false ? authToken : nil
        )
    }

    func releasesURL() -> URL {
        apiBaseURL
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent(owner, isDirectory: true)
            .appendingPathComponent(repository, isDirectory: true)
            .appendingPathComponent("releases", isDirectory: false)
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    var tagName: String
    var name: String?
    var draft: Bool
    var prerelease: Bool
    var createdAt: Date?
    var publishedAt: Date?
    var assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case draft
        case prerelease
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    var name: String
    var downloadURL: URL
    var digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }
}
