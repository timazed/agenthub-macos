import Foundation

struct AgentHubReleaseRequest: Codable, Equatable, Sendable {
    var codexVersion: String
    var codexArtifactURL: URL
    var codexSHA256: String
    var currentAgentHubVersion: String
    var releaseChannel: String
    var force: Bool
}

struct AgentHubReleaseResponse: Codable, Equatable, Sendable {
    var releaseJobID: UUID
    var status: String
    var codexVersion: String
    var targetAgentHubVersion: String
    var notes: [String]
}

struct AgentHubReleaseController {
    let worker: CodexReleaseWorker

    func bootstrapSummary() -> String {
        worker.bootstrapSummary()
    }

    func enqueueRelease(_ request: AgentHubReleaseRequest) throws -> AgentHubReleaseResponse {
        try worker.submit(request)
    }
}
