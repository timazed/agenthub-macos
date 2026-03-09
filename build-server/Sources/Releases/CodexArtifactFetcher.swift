import Foundation

enum CodexReleaseAssetKind: String, Equatable, Sendable {
    case darwinArm64
    case darwinX64
    case checksums
    case other
}

struct CodexReleaseAssetDescriptor: Equatable, Sendable {
    var name: String
    var downloadURL: URL
    var kind: CodexReleaseAssetKind
}

struct CodexArtifactDescriptor: Equatable, Sendable {
    var version: String
    var releaseTag: String
    var assets: [CodexReleaseAssetDescriptor]
}

enum CodexArtifactFetcherError: LocalizedError {
    case invalidConfiguration(String)
    case upstreamFetchFailed(String)
    case releaseNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case let .upstreamFetchFailed(message):
            return message
        case let .releaseNotFound(message):
            return message
        }
    }
}

struct CodexArtifactFetcher {
    var configurationProvider: @Sendable () throws -> GitHubReleasesConfiguration = {
        try GitHubReleasesConfiguration.fromEnvironment()
    }
    var releaseDataProvider: @Sendable (URLRequest) throws -> Data = { request in
        try URLSession.shared.codexSynchronousData(for: request)
    }

    func resolveLatestStableRelease() throws -> CodexArtifactDescriptor {
        let configuration = try configurationProvider()
        var request = URLRequest(url: configuration.releasesURL())
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AgentHubBuildServer/1.0", forHTTPHeaderField: "User-Agent")

        if let authToken = configuration.authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let data = try releaseDataProvider(request)
        let releases = try decodeReleases(from: data)

        guard let release = selectLatestStableRelease(from: releases) else {
            throw CodexArtifactFetcherError.releaseNotFound(
                "No stable Codex release found after filtering prereleases and -alpha tags"
            )
        }

        let assets = stableAssets(from: release)
        guard assets.isEmpty == false else {
            throw CodexArtifactFetcherError.releaseNotFound(
                "Latest stable Codex release \(release.tagName) has no usable non-alpha assets"
            )
        }

        return CodexArtifactDescriptor(
            version: normalizedVersion(from: release.tagName),
            releaseTag: release.tagName,
            assets: assets
        )
    }

    func decodeReleases(from data: Data) throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw CodexArtifactFetcherError.upstreamFetchFailed(
                "Failed to decode GitHub release response: \(error.localizedDescription)"
            )
        }
    }

    func selectLatestStableRelease(from releases: [GitHubRelease]) -> GitHubRelease? {
        releases
            .filter { release in
                release.draft == false &&
                release.prerelease == false &&
                containsAlphaMarker(release.tagName) == false &&
                stableAssets(from: release).isEmpty == false
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.publishedAt ?? lhs.createdAt ?? .distantPast
                let rhsDate = rhs.publishedAt ?? rhs.createdAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.tagName > rhs.tagName
            }
            .first
    }

    func stableAssets(from release: GitHubRelease) -> [CodexReleaseAssetDescriptor] {
        release.assets.compactMap { asset in
            guard containsAlphaMarker(asset.name) == false else {
                return nil
            }

            return CodexReleaseAssetDescriptor(
                name: asset.name,
                downloadURL: asset.downloadURL,
                kind: assetKind(for: asset.name)
            )
        }
    }

    func assetKind(for assetName: String) -> CodexReleaseAssetKind {
        let normalized = assetName.lowercased()
        if normalized.contains("checksums") || normalized.contains("sha256") {
            return .checksums
        }
        if isDarwinAsset(named: normalized), normalized.contains("arm64") || normalized.contains("aarch64") {
            return .darwinArm64
        }
        if isDarwinAsset(named: normalized), normalized.contains("x86_64") || normalized.contains("amd64") {
            return .darwinX64
        }
        return .other
    }

    func normalizedVersion(from tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v"), trimmed.count > 1 {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    func containsAlphaMarker(_ value: String) -> Bool {
        value.lowercased().contains("-alpha")
    }

    private func isDarwinAsset(named assetName: String) -> Bool {
        assetName.contains("darwin") || assetName.contains("macos") || assetName.contains("apple-darwin")
    }
}

private extension URLSession {
    func codexSynchronousData(for request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedResultBox<Result<Data, Error>>()

        let task = dataTask(with: request) { data, response, error in
            defer {
                semaphore.signal()
            }

            if let error {
                resultBox.store(
                    .failure(
                    CodexArtifactFetcherError.upstreamFetchFailed(
                        "Failed to fetch GitHub releases: \(error.localizedDescription)"
                    )
                )
                )
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                resultBox.store(
                    .failure(
                    CodexArtifactFetcherError.upstreamFetchFailed(
                        "GitHub releases response was not an HTTP response"
                    )
                )
                )
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                resultBox.store(
                    .failure(
                    CodexArtifactFetcherError.upstreamFetchFailed(
                        "GitHub releases request failed with status \(httpResponse.statusCode)"
                    )
                )
                )
                return
            }

            resultBox.store(.success(data))
        }

        task.resume()
        semaphore.wait()

        return try resultBox.load()?.get() ?? {
            throw CodexArtifactFetcherError.upstreamFetchFailed(
                "GitHub releases request completed without data"
            )
        }()
    }
}

private final class LockedResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func store(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
