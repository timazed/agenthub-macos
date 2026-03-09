import Foundation

struct CodexLaunchConfig {
    var agentHomeDirectory: String
    var codexHome: String
    var runtimeMode: RuntimeMode
    var externalDirectory: String?
    var enableSearch: Bool
    var model: String
    var reasoningEffort: ReasoningEffort
}

struct CodexExecutionResult {
    var threadId: String?
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

enum CodexEvent: Sendable {
    case started
    case threadIdentified(String)
    case stdoutLine(String)
    case stderrLine(String)
    case completed(Int32)
    case failed(String)
}

protocol CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult
    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult
    func streamEvents() -> AsyncStream<CodexEvent>
    func cancelCurrentRun() throws
}

enum CodexRuntimeError: LocalizedError {
    case busy
    case binaryNotFound
    case personaMissing(String)
    case repoMissing(String)
    case launchFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Codex runtime is already executing"
        case .binaryNotFound:
            return "Bundled codex binary not found"
        case let .personaMissing(path):
            return "Missing default persona AGENTS.md at \(path)"
        case let .repoMissing(path):
            return "External directory does not exist: \(path)"
        case let .launchFailed(message):
            return "Failed to launch Codex: \(message)"
        case .cancelled:
            return "Codex run cancelled"
        }
    }
}

final class CodexCLIRuntime: CodexRuntime {
    private struct StreamBuffer {
        var data = Data()
    }

    enum ParsedLine {
        case ignored
        case assistantText(String)
        case diagnostic(String)
        case threadId(String)
    }

    private let bundle: Bundle
    private let fileManager: FileManager
    private let stateLock = NSLock()
    private var continuation: AsyncStream<CodexEvent>.Continuation?
    private var currentProcess: Process?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
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

    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        try await execute(prompt: prompt, command: .startNewThread, config: config)
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        try await execute(prompt: prompt, command: .resume(threadId), config: config)
    }

    func cancelCurrentRun() throws {
        stateLock.lock()
        let process = currentProcess
        stateLock.unlock()
        process?.terminate()
    }

    private enum Command {
        case startNewThread
        case resume(String)
    }

    private func execute(prompt: String, command: Command, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        let codexURL = try locateCodexBinary()
        try validate(config: config)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runBlocking(codexURL: codexURL, prompt: prompt, command: command, config: config)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking(codexURL: URL, prompt: String, command: Command, config: CodexLaunchConfig) throws -> CodexExecutionResult {
        let process = Process()
        process.executableURL = codexURL
        process.arguments = buildArguments(prompt: prompt, command: command, config: config)

        process.currentDirectoryURL = URL(fileURLWithPath: config.agentHomeDirectory, isDirectory: true)

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = config.codexHome
        process.environment = environment

        let cwd = process.currentDirectoryURL?.path ?? config.agentHomeDirectory
        debugLog(
            codexHome: config.codexHome,
            message: "launch binary=\(codexURL.path) cwd=\(cwd) agentHomeDir=\(config.agentHomeDirectory) externalDir=\(config.externalDirectory ?? "<none>") mode=\(config.runtimeMode.rawValue) model=\(config.model) reasoning=\(config.reasoningEffort.rawValue) search=\(config.enableSearch) CODEX_HOME=\(config.codexHome) agents=\(personaDebugSummary(for: config.agentHomeDirectory)) args=\(process.arguments?.joined(separator: " ") ?? "<none>")"
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let historyOffset = currentHistoryOffset(codexHome: config.codexHome)
        let startedAt = Date()
        try appendRunnerLog(codexHome: config.codexHome, line: "start \(renderCommand(command: command, config: config))")

        var stdoutData = Data()
        var stderrData = Data()
        var stdoutBuffer = StreamBuffer()
        var stderrBuffer = StreamBuffer()
        let outputLock = NSLock()
        let finished = DispatchSemaphore(value: 0)

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            stdoutData.append(chunk)
            outputLock.unlock()
            self.emitLines(from: chunk, buffer: &stdoutBuffer, isStdErr: false)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            stderrData.append(chunk)
            outputLock.unlock()
            self.emitLines(from: chunk, buffer: &stderrBuffer, isStdErr: true)
        }

        process.terminationHandler = { _ in
            finished.signal()
        }

        stateLock.lock()
        guard currentProcess == nil else {
            stateLock.unlock()
            throw CodexRuntimeError.busy
        }
        currentProcess = process
        stateLock.unlock()

        emit(.started)

        do {
            try process.run()
        } catch {
            clearCurrentProcess()
            debugLog(codexHome: config.codexHome, message: "launch_failed error=\(String(describing: error))")
            throw CodexRuntimeError.launchFailed(String(describing: error))
        }

        _ = finished.wait(timeout: .distantFuture)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        outputLock.lock()
        stdoutData.append(remainingStdout)
        stderrData.append(remainingStderr)
        outputLock.unlock()
        emitLines(from: remainingStdout, buffer: &stdoutBuffer, isStdErr: false)
        emitLines(from: remainingStderr, buffer: &stderrBuffer, isStdErr: true)
        flushPartial(buffer: &stdoutBuffer, isStdErr: false)
        flushPartial(buffer: &stderrBuffer, isStdErr: true)

        let exitCode = process.terminationStatus
        clearCurrentProcess()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        try appendRunnerLog(codexHome: config.codexHome, line: "finish exit_code=\(exitCode) \(renderCommand(command: command, config: config))")

        if process.terminationReason == .uncaughtSignal && exitCode != 0 {
            emit(.failed(CodexRuntimeError.cancelled.localizedDescription))
            finishStream()
            throw CodexRuntimeError.cancelled
        }

        if exitCode != 0 {
            emit(.failed(stderr.isEmpty ? "Codex exited with code \(exitCode)" : stderr))
        }

        var threadId: String?
        if case .startNewThread = command {
            threadId = resolveThreadId(codexHome: config.codexHome, historyOffset: historyOffset, startedAt: startedAt)
            if let threadId {
                emit(.threadIdentified(threadId))
            }
        } else if case let .resume(existingThreadId) = command {
            threadId = existingThreadId
        }

        emit(.completed(exitCode))
        finishStream()
        return CodexExecutionResult(threadId: threadId, exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    private func validate(config: CodexLaunchConfig) throws {
        let agentsPath = URL(fileURLWithPath: config.agentHomeDirectory, isDirectory: true)
            .appendingPathComponent("AGENTS.md")
            .path
        guard fileManager.fileExists(atPath: agentsPath) else {
            throw CodexRuntimeError.personaMissing(agentsPath)
        }

        if config.runtimeMode == .task, let repoPath = config.externalDirectory {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: repoPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CodexRuntimeError.repoMissing(repoPath)
            }
        }
    }

    private func buildArguments(prompt: String, command: Command, config: CodexLaunchConfig) -> [String] {
        var args: [String] = [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--model", config.model,
            "-c", "model_reasoning_effort=\"\(config.reasoningEffort.rawValue)\"",
            "-C", config.agentHomeDirectory,
            "--sandbox", config.runtimeMode == .task ? "workspace-write" : "read-only"
        ]

        if config.enableSearch {
            args.append("--search")
        }

        if config.runtimeMode == .task, let repoPath = config.externalDirectory {
            args.append(contentsOf: ["--add-dir", repoPath])
        }

        switch command {
        case .startNewThread:
            args.append(prompt)
        case let .resume(threadId):
            args.append("resume")
            args.append(threadId)
            args.append(prompt)
        }

        return args
    }

    private func emit(_ event: CodexEvent) {
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

    private func emitLines(from chunk: Data, buffer: inout StreamBuffer, isStdErr: Bool) {
        guard !chunk.isEmpty else { return }
        buffer.data.append(chunk)

        while let range = buffer.data.firstRange(of: Data([0x0A])) {
            let lineData = buffer.data.subdata(in: 0..<range.lowerBound)
            let nextStart = range.upperBound
            buffer.data.removeSubrange(0..<nextStart)
            emitLine(data: lineData, isStdErr: isStdErr)
        }
    }

    private func flushPartial(buffer: inout StreamBuffer, isStdErr: Bool) {
        guard !buffer.data.isEmpty else { return }
        emitLine(data: buffer.data, isStdErr: isStdErr)
        buffer.data.removeAll(keepingCapacity: false)
    }

    private func emitLine(data: Data, isStdErr: Bool) {
        let rawLine = String(data: data, encoding: .utf8) ?? ""
        let cleaned = stripANSI(from: rawLine).trimmingCharacters(in: .newlines)
        guard !cleaned.isEmpty else { return }

        switch parseCodexLine(cleaned, isStdErr: isStdErr) {
        case .ignored:
            return
        case let .assistantText(text):
            emit(.stdoutLine(text))
        case let .diagnostic(text):
            emit(.stderrLine(text))
        case let .threadId(threadId):
            emit(.threadIdentified(threadId))
        }
    }

    func parseCodexLine(_ line: String, isStdErr: Bool) -> ParsedLine {
        if let parsed = parseStructuredJSONLine(from: line) {
            return parsed
        }

        if isStdErr {
            return shouldSurfaceDiagnostic(line) ? .diagnostic(line) : .ignored
        }

        return .assistantText(line)
    }

    func parseStructuredJSONLine(from line: String) -> ParsedLine? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        if let type = dictionary["type"] as? String {
            if let parsed = parseTypedJSONLine(type: type, dictionary: dictionary) {
                return parsed
            }
        }

        let method = dictionary["method"] as? String
        let params = dictionary["params"] as? [String: Any]

        if let threadId = extractThreadId(from: dictionary) ?? (params != nil ? extractThreadId(from: params as Any) : nil) {
            if method == "thread/started" || method == "thread/status/changed" {
                return .threadId(threadId)
            }
        }

        switch method {
        case "item/agentMessage/delta":
            if let text = extractAssistantText(from: params ?? dictionary) {
                return .assistantText(text)
            }
            return .ignored
        case "thread/realtime/error":
            if let text = extractDiagnosticText(from: params ?? dictionary) {
                return .diagnostic(text)
            }
            return .diagnostic(line)
        case "thread/started", "thread/status/changed", "item/started", "item/completed",
             "thread/tokenUsage/updated", "item/reasoning/summaryTextDelta",
             "item/reasoning/summaryPartAdded", "item/reasoning/textDelta":
            return .ignored
        default:
            if let text = extractAssistantText(from: params ?? dictionary) {
                return .assistantText(text)
            }
            if let diagnostic = extractDiagnosticText(from: params ?? dictionary) {
                return .diagnostic(diagnostic)
            }
            return .ignored
        }
    }

    private func parseTypedJSONLine(type: String, dictionary: [String: Any]) -> ParsedLine? {
        if let threadId = extractThreadId(from: dictionary),
           ["thread.started", "thread.updated", "thread.status.changed"].contains(type) {
            return .threadId(threadId)
        }

        switch type {
        case "item.delta", "item.completed":
            if let item = dictionary["item"],
               isAssistantMessagePayload(item),
               let text = extractAssistantText(from: item) {
                return .assistantText(text)
            }
            if isAssistantMessagePayload(dictionary),
               let text = extractAssistantText(from: dictionary) {
                return .assistantText(text)
            }
            return .ignored
        case "thread.error", "turn.error", "item.error":
            if let diagnostic = extractDiagnosticText(from: dictionary["item"] ?? dictionary) {
                return .diagnostic(diagnostic)
            }
            return .diagnostic(type)
        case "thread.started", "thread.updated", "thread.status.changed",
             "turn.started", "turn.completed", "item.started":
            return .ignored
        default:
            if let item = dictionary["item"],
               isAssistantMessagePayload(item),
               let text = extractAssistantText(from: item) {
                return .assistantText(text)
            }
            if let diagnostic = extractDiagnosticText(from: dictionary) {
                return .diagnostic(diagnostic)
            }
            return .ignored
        }
    }

    private func extractAssistantText(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["delta", "text", "content"] {
                if let string = dictionary[key] as? String,
                   shouldSurfaceAssistantText(string) {
                    return string
                }
            }

            if let item = dictionary["item"] {
                return extractAssistantText(from: item)
            }

            if let message = dictionary["message"] {
                return extractAssistantText(from: message)
            }

            if let content = dictionary["content"] {
                return extractAssistantText(from: content)
            }

            if let parts = dictionary["parts"] {
                return extractAssistantText(from: parts)
            }

            return nil
        }

        if let array = value as? [Any] {
            for item in array {
                if let text = extractAssistantText(from: item) {
                    return text
                }
            }
            return nil
        }

        if let string = value as? String, shouldSurfaceAssistantText(string) {
            return string
        }

        return nil
    }

    private func isAssistantMessagePayload(_ value: Any) -> Bool {
        guard let dictionary = value as? [String: Any] else {
            return false
        }

        if let itemType = (dictionary["type"] as? String)?.lowercased() {
            if itemType == "agent_message" || itemType == "assistant_message" {
                return true
            }
            if itemType.contains("message") == false {
                return false
            }
        }

        if let role = (dictionary["role"] as? String)?.lowercased(),
           role == "assistant" || role == "agent" {
            return true
        }

        if let message = dictionary["message"] {
            return isAssistantMessagePayload(message)
        }

        return dictionary["text"] != nil || dictionary["delta"] != nil || dictionary["content"] != nil
    }

    private func extractDiagnosticText(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["message", "error", "stderr", "stdout", "summary"] {
                if let string = dictionary[key] as? String,
                   shouldSurfaceDiagnostic(string) {
                    return string
                }
            }
            return nil
        }

        if let string = value as? String, shouldSurfaceDiagnostic(string) {
            return string
        }

        return nil
    }

    private func extractThreadId(from value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["threadId", "thread_id", "session_id", "sessionId"] {
                if let string = dictionary[key] as? String, !string.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private func shouldSurfaceAssistantText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let ignoredPrefixes = [
            "OpenAI Codex ",
            "workdir:",
            "model:",
            "provider:",
            "approval:",
            "sandbox:",
            "reasoning effort:",
            "reasoning summaries:",
            "session id:",
            "mcp startup:",
        ]

        return !ignoredPrefixes.contains { trimmed.hasPrefix($0) }
    }

    private func shouldSurfaceDiagnostic(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        if trimmed == "--------" { return false }
        if trimmed == "user" || trimmed == "codex" { return false }
        if trimmed.hasPrefix("openai codex ") { return false }
        if trimmed.hasPrefix("workdir:") { return false }
        if trimmed.hasPrefix("model:") { return false }
        if trimmed.hasPrefix("provider:") { return false }
        if trimmed.hasPrefix("approval:") { return false }
        if trimmed.hasPrefix("sandbox:") { return false }
        if trimmed.hasPrefix("reasoning effort:") { return false }
        if trimmed.hasPrefix("reasoning summaries:") { return false }
        if trimmed.hasPrefix("session id:") { return false }
        if trimmed.hasPrefix("mcp startup: no servers") { return false }
        if trimmed.hasPrefix("tokens used") { return false }
        return true
    }

    private func locateCodexBinary() throws -> URL {
        for candidate in codexBinaryCandidates() where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw CodexRuntimeError.binaryNotFound
    }

    private func clearCurrentProcess() {
        stateLock.lock()
        currentProcess = nil
        stateLock.unlock()
    }

    private func currentHistoryOffset(codexHome: String) -> UInt64 {
        let historyURL = URL(fileURLWithPath: codexHome, isDirectory: true).appendingPathComponent("history.jsonl")
        guard let attributes = try? fileManager.attributesOfItem(atPath: historyURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.uint64Value
    }

    private func resolveThreadId(codexHome: String, historyOffset: UInt64, startedAt: Date) -> String? {
        let historyURL = URL(fileURLWithPath: codexHome, isDirectory: true).appendingPathComponent("history.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: historyURL) else {
            return nil
        }
        defer { try? handle.close() }

        if historyOffset > 0 {
            try? handle.seek(toOffset: historyOffset)
        }

        let data = try? handle.readToEnd()
        guard let content = data.flatMap({ String(data: $0, encoding: .utf8) }) else {
            return nil
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            guard let sessionId = json["session_id"] as? String else {
                continue
            }

            if let ts = json["ts"] as? Double,
               Date(timeIntervalSince1970: ts) < startedAt.addingTimeInterval(-2) {
                continue
            }

            return sessionId
        }

        return nil
    }

    private func stripANSI(from text: String) -> String {
        let pattern = #"\u001B\[[0-9;?]*[ -/]*[@-~]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func renderCommand(command: Command, config: CodexLaunchConfig) -> String {
        var args = buildArguments(prompt: "<prompt>", command: command, config: config)
        if let last = args.last, last == "<prompt>" {
            args[args.count - 1] = "<prompt>"
        }
        return ([locateCodexBinaryPath()] + args).joined(separator: " ")
    }

    private func locateCodexBinaryPath() -> String {
        for candidate in codexBinaryCandidates() where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }

        return "<missing bundled codex>"
    }

    private func codexBinaryCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourcesURL = bundle.resourceURL {
            candidates.append(resourcesURL.appendingPathComponent("codex", isDirectory: false))
            candidates.append(resourcesURL.appendingPathComponent("codex/codex", isDirectory: false))
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        for entry in pathEntries {
            candidates.append(URL(fileURLWithPath: entry, isDirectory: true).appendingPathComponent("codex"))
        }
        return candidates
    }

    private func appendRunnerLog(codexHome: String, line: String) throws {
        let fileManager = FileManager.default
        let logsDirectory = URL(fileURLWithPath: codexHome, isDirectory: true).appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logURL = logsDirectory.appendingPathComponent("codex-runner.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(timestamp)] \(line)\n".utf8)

        if !fileManager.fileExists(atPath: logURL.path) {
            try data.write(to: logURL, options: [.atomic])
            return
        }

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private func personaDebugSummary(for personaDirectory: String) -> String {
        let agentsURL = URL(fileURLWithPath: personaDirectory, isDirectory: true).appendingPathComponent("AGENTS.md")
        guard fileManager.fileExists(atPath: agentsURL.path) else {
            return "missing:\(agentsURL.path)"
        }

        let previewText = (try? String(contentsOf: agentsURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "<unreadable>"
        return "path=\(agentsURL.path) preview=\(preview(previewText, limit: 160))"
    }

    private func debugLog(codexHome: String, message: String) {
        let line = "[AgentHub][CodexRuntime] \(message)"
        print(line)
        try? appendRunnerLog(codexHome: codexHome, line: line)
    }

    private func preview(_ text: String, limit: Int = 500) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: "\\n")
        if singleLine.count <= limit {
            return singleLine
        }

        let end = singleLine.index(singleLine.startIndex, offsetBy: limit)
        return "\(singleLine[..<end])..."
    }
}
