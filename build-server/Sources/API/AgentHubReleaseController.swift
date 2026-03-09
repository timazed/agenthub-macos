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

    func prepareArtifacts(_ request: AgentHubReleaseRequest) throws -> AgentHubArtifactPreparation {
        try worker.releaseService.prepareArtifacts(request: request)
    }

    func planRelease(_ request: AgentHubReleaseRequest) throws -> AgentHubReleasePlan {
        try worker.releaseService.prepareRelease(request: request)
    }

    func enqueueRelease(_ request: AgentHubReleaseRequest) throws -> AgentHubReleaseResponse {
        try worker.submit(request)
    }
}
