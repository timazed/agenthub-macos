import Foundation
import Darwin

let controller = AgentHubReleaseController(
    worker: CodexReleaseWorker(
        releaseService: AgentHubReleaseService()
    )
)

let cli = BuildServerCLI(
    arguments: Array(CommandLine.arguments.dropFirst()),
    planRelease: { request in
        try controller.planRelease(request)
    },
    output: { message in
        print(message)
    }
)

do {
    try cli.run()
} catch {
    let message = error.localizedDescription
    fputs("\(message)\n", stderr)
    fputs("\(BuildServerCLI.usageText)\n", stderr)
    exit(1)
}
