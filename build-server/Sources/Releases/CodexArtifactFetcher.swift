import Foundation

struct CodexArtifactDescriptor: Equatable, Sendable {
    var version: String
    var releaseTag: String
}

struct CodexArtifactFetcher {
    var latestStableReleaseProvider: @Sendable () -> CodexArtifactDescriptor = {
        CodexArtifactDescriptor(
            version: "latest",
            releaseTag: "latest"
        )
    }

    func resolveLatestStableRelease() -> CodexArtifactDescriptor {
        latestStableReleaseProvider()
    }
}
