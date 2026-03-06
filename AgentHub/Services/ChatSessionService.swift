import Foundation

enum ChatSessionEvent {
    case assistantDelta(String)
    case stderr(String)
    case proposal(TaskProposal)
    case completed
    case failed(String)
}

final class ChatSessionService {
    private let sessionStore: AssistantSessionStore
    private let personaManager: PersonaManager
    private let runtime: CodexRuntime
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore

    private let stateLock = NSLock()
    private var continuation: AsyncStream<ChatSessionEvent>.Continuation?

    init(
        sessionStore: AssistantSessionStore,
        personaManager: PersonaManager,
        runtime: CodexRuntime,
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore
    ) {
        self.sessionStore = sessionStore
        self.personaManager = personaManager
        self.runtime = runtime
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
    }

    func loadMessages() throws -> [Message] {
        try sessionStore.loadMessages()
    }

    func streamEvents() -> AsyncStream<ChatSessionEvent> {
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

    func cancelCurrentRun() throws {
        try runtime.cancelCurrentRun()
    }

    func sendUserMessage(_ text: String) async throws {
        defer { finishStream() }

        let persona = try personaManager.defaultPersona()
        var session = try sessionStore.loadOrCreateDefault(personaId: persona.id)

        let userMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .user,
            text: text,
            source: .userInput,
            createdAt: Date()
        )
        try sessionStore.appendMessage(userMessage)

        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: .chatOnly,
            externalDirectory: nil,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )

        let prompt = buildChatPrompt(userText: text)
        let runtimeStream = runtime.streamEvents()

        var assistantText = ""
        var stderrText = ""

        let bridgeTask = Task {
            for await event in runtimeStream {
                switch event {
                case let .stdoutLine(line):
                    assistantText += assistantText.isEmpty ? line : "\n\(line)"
                    emit(.assistantDelta(line))
                case let .stderrLine(line):
                    stderrText += stderrText.isEmpty ? line : "\n\(line)"
                    emit(.stderr(line))
                case let .threadIdentified(threadId):
                    session.codexThreadId = threadId
                    session.updatedAt = Date()
                    try? sessionStore.save(session)
                case .started, .completed:
                    break
                case let .failed(message):
                    emit(.failed(message))
                }
            }
        }

        let result: CodexExecutionResult
        if let threadId = session.codexThreadId {
            result = try await runtime.resumeThread(threadId: threadId, prompt: prompt, config: launchConfig)
        } else {
            result = try await runtime.startNewThread(prompt: prompt, config: launchConfig)
            if let threadId = result.threadId {
                session.codexThreadId = threadId
            }
        }

        _ = await bridgeTask.result

        session.updatedAt = Date()
        try sessionStore.save(session)

        let parsed = parseAssistantResponse(assistantText)
        let assistantMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            text: parsed.displayText.isEmpty ? assistantText : parsed.displayText,
            source: .codexStdout,
            createdAt: Date()
        )
        try sessionStore.appendMessage(assistantMessage)

        if let proposal = parsed.proposal {
            emit(.proposal(proposal))
        }

        if result.exitCode != 0 {
            let message = stderrText.isEmpty ? "Chat failed with exit code \(result.exitCode)" : stderrText
            emit(.failed(message))
            return
        }

        emit(.completed)
    }

    private func buildChatPrompt(userText: String) -> String {
        """
        FORMAT INSTRUCTION:
        If and only if the user is clearly asking to create a recurring or background task, append exactly one XML block at the end of your response:
        <agenthub_task_proposal>{"title":"...","instructions":"...","scheduleType":"manual|intervalMinutes|dailyAtHHMM","scheduleValue":"...","runtimeMode":"chatOnly|task","repoPath":null,"runNow":false}</agenthub_task_proposal>
        Do not mention the XML block in your prose.
        Do not restate or override instructions already provided by AGENTS.md.

        USER:
        \(userText)
        """
    }

    private func parseAssistantResponse(_ text: String) -> (displayText: String, proposal: TaskProposal?) {
        let pattern = #"<agenthub_task_proposal>([\s\S]*?)</agenthub_task_proposal>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let proposalRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let payload = String(text[proposalRange])
        let stripped = text.replacingCharacters(in: fullRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TaskProposalPayload.self, from: data) else {
            return (stripped, nil)
        }

        let proposal = TaskProposal(
            id: UUID(),
            title: decoded.title,
            instructions: decoded.instructions,
            scheduleType: decoded.scheduleType,
            scheduleValue: decoded.scheduleValue,
            runtimeMode: decoded.runtimeMode,
            repoPath: decoded.externalDirectory ?? decoded.repoPath,
            runNow: decoded.runNow
        )
        return (stripped, proposal)
    }

    private func emit(_ event: ChatSessionEvent) {
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
}

private struct TaskProposalPayload: Decodable {
    var title: String
    var instructions: String
    var scheduleType: TaskScheduleType
    var scheduleValue: String
    var runtimeMode: RuntimeMode
    var externalDirectory: String?
    var repoPath: String?
    var runNow: Bool
}
