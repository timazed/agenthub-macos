import Foundation

struct BuildServerRunSummary: Codable, Equatable, Sendable {
    var releaseJobID: UUID
    var status: String
    var codexVersion: String
    var resolvedReleaseTag: String
    var targetAgentHubVersion: String
    var targetBuildNumber: Int
    var derivedDataPath: String
    var appBundlePath: String
    var injectedBinaryPath: String
    var universalBinaryPath: String
    var notes: [String]
}

enum BuildServerCLIError: LocalizedError {
    case usage(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            return message
        case let .invalidArgument(message):
            return message
        }
    }
}

struct BuildServerCLI {
    enum OutputMode: Equatable {
        case text
        case json
    }

    var arguments: [String]
    var planRelease: (AgentHubReleaseRequest) throws -> AgentHubReleasePlan
    var output: (String) -> Void

    func run() throws {
        let parsed = try parse(arguments: arguments)

        switch parsed {
        case .help:
            output(Self.usageText)
        case let .prepareRelease(request, outputMode):
            let plan = try planRelease(request)
            let summary = BuildServerRunSummary(
                releaseJobID: plan.jobID,
                status: "prepared",
                codexVersion: plan.codexRelease.version,
                resolvedReleaseTag: plan.codexRelease.releaseTag,
                targetAgentHubVersion: plan.targetAgentHubVersion,
                targetBuildNumber: plan.targetBuildNumber,
                derivedDataPath: plan.buildResult.derivedDataURL.path,
                appBundlePath: plan.buildResult.appBundleURL.path,
                injectedBinaryPath: plan.bundleInjectionResult.injectedBinaryURL.path,
                universalBinaryPath: plan.preparedArtifacts.universalBinaryURL.path,
                notes: plan.steps
            )
            output(render(summary: summary, mode: outputMode))
        }
    }

    func parse(arguments: [String]) throws -> ParsedCommand {
        guard arguments.isEmpty == false else {
            return .help
        }

        if arguments.contains("--help") || arguments.contains("-h") {
            return .help
        }

        var iterator = arguments.makeIterator()
        guard let command = iterator.next() else {
            return .help
        }

        switch command {
        case "prepare-release":
            var currentAgentHubVersion: String?
            var currentBuildNumber: Int?
            var releaseChannel: String?
            var force = false
            var outputMode: OutputMode = .text

            while let argument = iterator.next() {
                switch argument {
                case "--agenthub-version":
                    currentAgentHubVersion = try nextValue(after: argument, iterator: &iterator)
                case "--build-number":
                    let rawValue = try nextValue(after: argument, iterator: &iterator)
                    guard let parsedValue = Int(rawValue) else {
                        throw BuildServerCLIError.invalidArgument(
                            "Invalid --build-number value: \(rawValue)"
                        )
                    }
                    currentBuildNumber = parsedValue
                case "--channel":
                    releaseChannel = try nextValue(after: argument, iterator: &iterator)
                case "--force":
                    force = true
                case "--json":
                    outputMode = .json
                default:
                    throw BuildServerCLIError.invalidArgument("Unknown argument: \(argument)")
                }
            }

            guard let currentAgentHubVersion else {
                throw BuildServerCLIError.usage("Missing required --agenthub-version")
            }
            guard let currentBuildNumber else {
                throw BuildServerCLIError.usage("Missing required --build-number")
            }
            guard let releaseChannel else {
                throw BuildServerCLIError.usage("Missing required --channel")
            }

            return .prepareRelease(
                AgentHubReleaseRequest(
                    currentAgentHubVersion: currentAgentHubVersion,
                    currentBuildNumber: currentBuildNumber,
                    releaseChannel: releaseChannel,
                    force: force
                ),
                outputMode
            )
        default:
            throw BuildServerCLIError.usage("Unknown command: \(command)")
        }
    }

    func render(summary: BuildServerRunSummary, mode: OutputMode) -> String {
        switch mode {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try? encoder.encode(summary)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        case .text:
            return """
            agenthub-build-server

            Status: \(summary.status)
            Codex version: \(summary.codexVersion) (\(summary.resolvedReleaseTag))
            Target AgentHub version: \(summary.targetAgentHubVersion) (\(summary.targetBuildNumber))
            DerivedData: \(summary.derivedDataPath)
            App bundle: \(summary.appBundlePath)
            Injected binary: \(summary.injectedBinaryPath)
            Universal binary: \(summary.universalBinaryPath)

            Steps:
            \(summary.notes.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
    }

    private func nextValue(
        after argument: String,
        iterator: inout IndexingIterator<[String]>
    ) throws -> String {
        guard let value = iterator.next() else {
            throw BuildServerCLIError.usage("Missing value after \(argument)")
        }
        return value
    }

    static let usageText = """
    agenthub-build-server

    Usage:
      agenthub-build-server prepare-release --agenthub-version <version> --build-number <number> --channel <stable|dev> [--force] [--json]
      agenthub-build-server --help
    """

    enum ParsedCommand: Equatable {
        case help
        case prepareRelease(AgentHubReleaseRequest, OutputMode)
    }
}
