import Foundation

final class ClaudeAuthProviderClient: AuthProviderClient {
    let provider: AuthProvider = .claude
    let capabilities = ProviderCapabilities.available(
        authMethods: [.externalSetup],
        supportsChat: true,
        supportsScheduledTasks: false
    )

    private let paths: AppPaths
    private let bundle: Bundle
    private let fileManager: FileManager
    private let loginCoordinator: ClaudeLoginCoordinator

    init(
        paths: AppPaths,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.bundle = bundle
        self.fileManager = fileManager
        self.loginCoordinator = ClaudeLoginCoordinator(
            statusRefresher: {
                try Self.refreshClaudeStatus(paths: paths, bundle: bundle, fileManager: fileManager)
            },
            paths: paths,
            bundle: bundle,
            fileManager: fileManager
        )
    }

    func refreshStatus() throws -> AuthState {
        try Self.refreshClaudeStatus(paths: paths, bundle: bundle, fileManager: fileManager)
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        try await loginCoordinator.startLogin()
        return nil
    }

    func waitForLoginCompletion() async throws -> AuthState {
        try await loginCoordinator.waitForCompletion()
    }

    func cancelLogin() {
        loginCoordinator.cancel()
    }

    private struct ClaudeAuthStatusResponse: Decodable {
        var loggedIn: Bool
        var authMethod: String?
        var apiProvider: String?
        var accountEmail: String?
        var email: String?
    }

    private static func refreshClaudeStatus(
        paths: AppPaths?,
        bundle: Bundle,
        fileManager: FileManager
    ) throws -> AuthState {
        let claudeURL = try locateClaudeBinary(bundle: bundle, fileManager: fileManager)
        if let paths {
            try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        }
        let process = Process()
        process.executableURL = claudeURL
        process.arguments = ["auth", "status"]
        if let paths {
            process.currentDirectoryURL = paths.root
            process.environment = ClaudeRuntime.buildEnvironment(claudeHome: paths.root.path)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AssistantRuntimeError.launchFailed(String(describing: error))
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let response = decodeStatus(stdout: stdout, stderr: stderr) else {
            let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw AssistantRuntimeError.launchFailed(
                combined.isEmpty ? "Unable to determine Claude login status" : combined
            )
        }

        let now = Date()
        let accountLabel = response.accountEmail ?? response.email
        return AuthState(
            provider: .claude,
            status: response.loggedIn ? .authenticated : .unauthenticated,
            accountLabel: accountLabel,
            lastValidatedAt: response.loggedIn ? now : nil,
            failureReason: response.loggedIn ? nil : "Sign in to Claude to continue.",
            updatedAt: now
        )
    }

    private static func decodeStatus(stdout: String, stderr: String) -> ClaudeAuthStatusResponse? {
        let decoder = JSONDecoder()
        for candidate in [stdout, stderr] where !candidate.isEmpty {
            if let data = candidate.data(using: .utf8),
               let response = try? decoder.decode(ClaudeAuthStatusResponse.self, from: data) {
                return response
            }
        }
        return nil
    }

    private static func locateClaudeBinary(bundle: Bundle, fileManager: FileManager) throws -> URL {
        if let resourcesURL = bundle.resourceURL {
            let candidates = [
                resourcesURL.appendingPathComponent("claude", isDirectory: false),
                resourcesURL.appendingPathComponent("claude/claude", isDirectory: false),
            ]

            for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let workspaceCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("AgentHub/Resources/claude/claude", isDirectory: false)
        if fileManager.isExecutableFile(atPath: workspaceCandidate.path) {
            return workspaceCandidate
        }

        throw AssistantRuntimeError.launchFailed("Bundled claude binary not found")
    }
}
