import Foundation

let controller = AgentHubReleaseController(
    worker: CodexReleaseWorker(
        releaseService: AgentHubReleaseService()
    )
)

if CommandLine.arguments.contains("--help") {
    print(
        """
        agenthub-build-server

        Scaffolds the future AgentHub release flow that will resolve the latest
        stable Codex GitHub release, package a new app build, and publish it.
        """
    )
} else {
    let bootstrapState = controller.bootstrapSummary()
    print("AgentHub build server scaffold ready: \(bootstrapState)")
}
