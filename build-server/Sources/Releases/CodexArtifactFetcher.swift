import Foundation

struct CodexArtifactDescriptor: Equatable, Sendable {
    var version: String
    var sourceURL: URL
    var sha256: String
}

struct CodexArtifactFetcher {
    func describe(request: AgentHubReleaseRequest) -> CodexArtifactDescriptor {
        CodexArtifactDescriptor(
            version: request.codexVersion,
            sourceURL: request.codexArtifactURL,
            sha256: request.codexSHA256
        )
    }
}
