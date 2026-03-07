import Foundation

final class ClaudeRuntime: AssistantRuntime {
    private let bundle: Bundle
    private let fileManager: FileManager
    private let stateLock = NSLock()
    private var continuation: AsyncStream<AssistantEvent>.Continuation?
    private var currentProcess: Process?

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func streamEvents() -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            stateLock.lock()
            self.continuation = continuation
            stateLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.stateLock.lock()
                self.continuation = nil
                self.stateLock.unlock()
            }
        }
    }

    func startNewThread(prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        try validate(config: config)
        let sessionID = UUID().uuidString.lowercased()
        return try await execute(
            prompt: prompt,
            threadID: sessionID,
            command: .startNewThread(sessionID),
            config: config
        )
    }

    func resumeThread(threadId: String, prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        try validate(config: config)
        return try await execute(
            prompt: prompt,
            threadID: threadId,
            command: .resume(threadId),
            config: config
        )
    }

    func checkLoginStatus(codexHome: String) throws -> AssistantLoginStatusResult {
        let claudeURL = try locateClaudeBinary()
        let claudeHomeURL = URL(fileURLWithPath: codexHome, isDirectory: true)
        try fileManager.createDirectory(at: claudeHomeURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = claudeURL
        process.arguments = ["auth", "status"]
        process.environment = Self.buildEnvironment(claudeHome: codexHome)

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

        guard let response = Self.decodeStatus(stdout: stdout, stderr: stderr) else {
            let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw AssistantRuntimeError.launchFailed(
                combined.isEmpty ? "Unable to determine Claude login status" : combined
            )
        }

        return AssistantLoginStatusResult(
            isAuthenticated: response.loggedIn,
            accountEmail: response.accountEmail ?? response.email,
            message: response.loggedIn ? nil : "Sign in to Claude to continue."
        )
    }

    func cancelCurrentRun() throws {
        stateLock.lock()
        let process = currentProcess
        stateLock.unlock()
        process?.terminate()
    }

    enum Command {
        case startNewThread(String)
        case resume(String)
    }

    private struct ClaudeAuthStatusResponse: Decodable {
        var loggedIn: Bool
        var accountEmail: String?
        var email: String?
    }

    private func execute(
        prompt: String,
        threadID: String,
        command: Command,
        config: AssistantLaunchConfig
    ) async throws -> AssistantExecutionResult {
        let claudeURL = try locateClaudeBinary()
        let personaInstructions = try loadPersonaInstructions(from: config.agentHomeDirectory)
        try fileManager.createDirectory(at: URL(fileURLWithPath: config.codexHome, isDirectory: true), withIntermediateDirectories: true)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runBlocking(
                        claudeURL: claudeURL,
                        prompt: prompt,
                        threadID: threadID,
                        command: command,
                        config: config,
                        personaInstructions: personaInstructions
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking(
        claudeURL: URL,
        prompt: String,
        threadID: String,
        command: Command,
        config: AssistantLaunchConfig,
        personaInstructions: String
    ) throws -> AssistantExecutionResult {
        let process = Process()
        process.executableURL = claudeURL
        process.arguments = Self.buildArguments(
            prompt: prompt,
            command: command,
            config: config,
            personaInstructions: personaInstructions
        )
        process.currentDirectoryURL = URL(fileURLWithPath: config.agentHomeDirectory, isDirectory: true)
        process.environment = Self.buildEnvironment(claudeHome: config.codexHome)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let outputLock = NSLock()
        let finished = DispatchSemaphore(value: 0)

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            stdoutData.append(chunk)
            outputLock.unlock()
            self?.emitLines(from: chunk, isStdErr: false)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            stderrData.append(chunk)
            outputLock.unlock()
            self?.emitLines(from: chunk, isStdErr: true)
        }

        process.terminationHandler = { _ in
            finished.signal()
        }

        stateLock.lock()
        guard currentProcess == nil else {
            stateLock.unlock()
            throw AssistantRuntimeError.busy
        }
        currentProcess = process
        stateLock.unlock()

        emit(.started)
        if case .startNewThread = command {
            emit(.threadIdentified(threadID))
        }

        do {
            try process.run()
        } catch {
            clearCurrentProcess()
            throw AssistantRuntimeError.launchFailed(String(describing: error))
        }

        _ = finished.wait(timeout: .distantFuture)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        outputLock.lock()
        stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        outputLock.unlock()

        let exitCode = process.terminationStatus
        clearCurrentProcess()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if process.terminationReason == .uncaughtSignal && exitCode != 0 {
            emit(.failed(AssistantRuntimeError.cancelled.localizedDescription))
            finishStream()
            throw AssistantRuntimeError.cancelled
        }

        if exitCode != 0 {
            emit(.failed(stderr.isEmpty ? "Claude exited with code \(exitCode)" : stderr))
        }

        emit(.completed(exitCode))
        finishStream()

        return AssistantExecutionResult(
            threadId: threadID,
            exitCode: exitCode,
            stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func validate(config: AssistantLaunchConfig) throws {
        _ = try loadPersonaInstructions(from: config.agentHomeDirectory)

        if config.runtimeMode == .task {
            throw AssistantRuntimeError.launchFailed("Claude scheduled tasks are not supported yet.")
        }
    }

    private func loadPersonaInstructions(from directory: String) throws -> String {
        let agentsURL = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("AGENTS.md")
        guard fileManager.fileExists(atPath: agentsURL.path) else {
            throw AssistantRuntimeError.personaMissing(agentsURL.path)
        }
        return try String(contentsOf: agentsURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func buildArguments(
        prompt: String,
        command: Command,
        config: AssistantLaunchConfig,
        personaInstructions: String
    ) -> [String] {
        var args = [
            "-p",
            "--output-format", "text",
            "--dangerously-skip-permissions",
            "--permission-mode", "bypassPermissions",
            "--append-system-prompt", personaInstructions
        ]

        if let model = mapModel(config.model) {
            args.append(contentsOf: ["--model", model])
        }

        switch command {
        case let .startNewThread(sessionID):
            args.append(contentsOf: ["--session-id", sessionID])
        case let .resume(sessionID):
            args.append(contentsOf: ["--resume", sessionID])
        }

        if let repoPath = config.externalDirectory, !repoPath.isEmpty {
            args.append(contentsOf: ["--add-dir", repoPath])
        }

        args.append(prompt)
        return args
    }

    static func mapModel(_ configuredModel: String) -> String? {
        let trimmed = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased().contains("claude") ? trimmed : nil
    }

    static func buildEnvironment(claudeHome: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = claudeHome
        environment["XDG_CONFIG_HOME"] = claudeHome
        return environment
    }

    private func emit(_ event: AssistantEvent) {
        stateLock.lock()
        let continuation = continuation
        stateLock.unlock()
        continuation?.yield(event)
    }

    private func finishStream() {
        stateLock.lock()
        let continuation = continuation
        self.continuation = nil
        stateLock.unlock()
        continuation?.finish()
    }

    private func clearCurrentProcess() {
        stateLock.lock()
        currentProcess = nil
        stateLock.unlock()
    }

    private func emitLines(from chunk: Data, isStdErr: Bool) {
        guard let text = String(data: chunk, encoding: .utf8) else { return }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            emit(isStdErr ? .stderrLine(line) : .stdoutLine(line))
        }
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

    private func locateClaudeBinary() throws -> URL {
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
