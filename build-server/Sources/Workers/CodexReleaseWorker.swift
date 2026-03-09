import Foundation

struct CodexReleaseWorker {
    let releaseService: AgentHubReleaseService

    func bootstrapSummary() -> String {
        "release controller + worker + planning services"
    }

    func submit(_ request: AgentHubReleaseRequest) throws -> AgentHubReleaseResponse {
        let releasePlan = releaseService.prepareRelease(request: request)

        return AgentHubReleaseResponse(
            releaseJobID: releasePlan.jobID,
            status: "queued",
            codexVersion: request.codexVersion,
            targetAgentHubVersion: releasePlan.targetAgentHubVersion,
            notes: releasePlan.steps
        )
    }
}
