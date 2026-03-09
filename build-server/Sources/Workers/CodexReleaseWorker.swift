import Foundation

struct CodexReleaseWorker {
    let releaseService: AgentHubReleaseService

    func bootstrapSummary() -> String {
        "release controller + worker + latest stable Codex release planning"
    }

    func submit(_ request: AgentHubReleaseRequest) throws -> AgentHubReleaseResponse {
        let releasePlan = try releaseService.prepareRelease(request: request)

        return AgentHubReleaseResponse(
            releaseJobID: releasePlan.jobID,
            status: "queued",
            codexVersion: releasePlan.codexRelease.version,
            resolvedReleaseTag: releasePlan.codexRelease.releaseTag,
            targetAgentHubVersion: releasePlan.targetAgentHubVersion,
            targetBuildNumber: releasePlan.targetBuildNumber,
            notes: releasePlan.steps
        )
    }
}
