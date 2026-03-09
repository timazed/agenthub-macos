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

        Scaffolds the future AgentHub release flow that will package a new app build
        whenever a Codex release is detected.
        """
    )
} else {
    let bootstrapState = controller.bootstrapSummary()
    print("AgentHub build server scaffold ready: \(bootstrapState)")
}
