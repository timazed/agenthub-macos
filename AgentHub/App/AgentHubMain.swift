import AppKit
import Foundation
import SwiftUI

@main
enum AgentHubMain {
    static func main() {
        let cefExitCode = AHChromiumMaybeRunSubprocess(CommandLine.argc, CommandLine.unsafeArgv)
        if cefExitCode >= 0 {
            Foundation.exit(cefExitCode)
        }

        let args = CommandLine.arguments
        appendStartupLog("argv=\(args.joined(separator: " "))")

        if let taskId = parseTaskId(args: args) {
            appendStartupLog("entry=headless task_id=\(taskId.uuidString)")
            let exitCode = runAsyncMainLoop {
                await HeadlessTaskCommand().run(taskId: taskId)
            }
            AHChromiumShutdownRuntime()
            Foundation.exit(exitCode)
        }

        if let scenarioSelection = parseScenarioSelection(args: args) {
            appendStartupLog("entry=headless browser_scenario=\(scenarioSelection.selection)")
            AHChromiumInstallApplicationClass()
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let exitCode = runAsyncMainLoop {
                await HeadlessBrowserScenarioCommand().run(
                    selection: scenarioSelection.selection,
                    scenarioFilePath: scenarioSelection.filePath
                )
            }
            AHChromiumShutdownRuntime()
            Foundation.exit(exitCode)
        }

        appendStartupLog("entry=gui")
        AHChromiumInstallApplicationClass()
        AgentHubApp.main()
    }

    private static func parseTaskId(args: [String]) -> UUID? {
        guard let index = args.firstIndex(of: "--run-task"), args.indices.contains(index + 1) else {
            return nil
        }
        return UUID(uuidString: args[index + 1])
    }

    private static func parseScenarioSelection(args: [String]) -> (selection: String, filePath: String?)? {
        guard let index = args.firstIndex(of: "--run-browser-scenario"), args.indices.contains(index + 1) else {
            return nil
        }
        let selection = args[index + 1]
        let fileIndex = args.firstIndex(of: "--scenario-file")
        let filePath = fileIndex.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        return (selection, filePath)
    }

    private static func appendStartupLog(_ line: String) {
        let fileManager = FileManager.default
        let logsDirectory = AppPaths.defaultRoot().appendingPathComponent("logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("startup.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload = Data("[\(timestamp)] [AgentHub][Main] \(line)\n".utf8)

        if !fileManager.fileExists(atPath: logURL.path) {
            try? payload.write(to: logURL, options: [.atomic])
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: payload)
        try? handle.close()
    }

    private static func runAsyncMainLoop(_ operation: @escaping () async -> Int32) -> Int32 {
        final class CompletionBox {
            var exitCode: Int32?
        }

        let box = CompletionBox()
        Task {
            box.exitCode = await operation()
        }

        while box.exitCode == nil {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return box.exitCode ?? 1
    }
}

struct HeadlessTaskCommand {
    func run(taskId: UUID) async -> Int32 {
        var container: AppContainer?
        let exitCode: Int32
        do {
            let resolvedContainer = try AppContainer.makeHeadless()
            container = resolvedContainer
            await MainActor.run {
                resolvedContainer.installHeadlessBrowserHostIfNeeded()
            }
            exitCode = await resolvedContainer.scheduleRunner.runTask(taskId: taskId)
        } catch {
            fputs("Headless task failed: \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }

        if let container {
            await MainActor.run {
                container.teardownHeadlessBrowserHost()
                container.browserController.prepareForShutdown()
            }
        }

        return exitCode
    }
}

struct HeadlessBrowserScenarioCommand {
    func run(selection: String, scenarioFilePath: String?) async -> Int32 {
        var container: AppContainer?
        let exitCode: Int32
        do {
            let resolvedContainer = try AppContainer.makeHeadless()
            container = resolvedContainer
            await MainActor.run {
                resolvedContainer.installHeadlessBrowserHostIfNeeded()
            }
            let scenarioFileURL = URL(fileURLWithPath: scenarioFilePath ?? defaultScenarioFilePath())
            let scenarios = try BrowserSmokeScenarioManifest.load(from: scenarioFileURL)
            let chosenScenarios: [BrowserSmokeScenarioDefinition]
            if selection == "all" {
                chosenScenarios = scenarios
            } else {
                guard let scenario = scenarios.first(where: { $0.id == selection }) else {
                    throw ChromiumBrowserActionError(message: "Unknown browser smoke scenario: \(selection)")
                }
                chosenScenarios = [scenario]
            }

            for scenario in chosenScenarios {
                let summary = try await resolvedContainer.chatSessionService.runBrowserScenario(scenario)
                print("[browser-scenario] \(summary.scenarioID) \(summary.outcome) \(summary.finalSummary)")
            }
            exitCode = 0
        } catch {
            fputs("Headless browser scenario failed: \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }

        if let container {
            await MainActor.run {
                container.teardownHeadlessBrowserHost()
                container.browserController.prepareForShutdown()
            }
        }

        return exitCode
    }

    private func defaultScenarioFilePath() -> String {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent("docs/browser-live-smoke-scenarios.json").path
    }
}
