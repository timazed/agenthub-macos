import Foundation

struct AgentHubReleaseRequest: Codable, Equatable, Sendable {
    var currentAgentHubVersion: String
    var currentBuildNumber: Int
    var releaseChannel: String
    var force: Bool
}

struct AgentHubReleaseResponse: Codable, Equatable, Sendable {
    var releaseJobID: UUID
    var status: String
    var codexVersion: String
    var resolvedReleaseTag: String
    var targetAgentHubVersion: String
    var targetBuildNumber: Int
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
