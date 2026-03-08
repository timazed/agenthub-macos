import Foundation

final class ExternalAgentExecutionService {
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let sessionStore: AssistantSessionStore
    private let paths: AppPaths
    private let runtimeFactory: () -> CodexRuntime

    init(
        runtimeConfigStore: AppRuntimeConfigStore,
        sessionStore: AssistantSessionStore,
        paths: AppPaths,
        runtimeFactory: @escaping () -> CodexRuntime
    ) {
        self.runtimeConfigStore = runtimeConfigStore
        self.sessionStore = sessionStore
        self.paths = paths
        self.runtimeFactory = runtimeFactory
    }

    func execute(persona: Persona, prompt: String) async throws -> String {
        let runtime = runtimeFactory()
        var session = try sessionStore.loadOrCreateDefault(personaId: persona.id)
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

        var assistantText = ""
        var stderrText = ""

        let bridgeTask = Task {
            for await event in runtime.streamEvents() {
                switch event {
                case let .stdoutLine(line):
                    assistantText += assistantText.isEmpty ? line : "\n\(line)"
                case let .stderrLine(line):
                    stderrText += stderrText.isEmpty ? line : "\n\(line)"
                case let .failed(message):
                    stderrText += stderrText.isEmpty ? message : "\n\(message)"
                case .started, .completed, .threadIdentified:
                    break
                }
            }
        }

        let result: CodexExecutionResult
        if let threadID = session.codexThreadId {
            result = try await runtime.resumeThread(
                threadId: threadID,
                prompt: buildPrompt(userText: prompt),
                config: launchConfig
            )
        } else {
            result = try await runtime.startNewThread(
                prompt: buildPrompt(userText: prompt),
                config: launchConfig
            )
            if let threadID = result.threadId {
                session.codexThreadId = threadID
            }
        }

        _ = await bridgeTask.result
        if let threadID = result.threadId {
            session.codexThreadId = threadID
        }
        session.updatedAt = Date()
        try sessionStore.save(session)

        let rawResponse = assistantText.isEmpty ? result.stdout : assistantText
        let parsed = parseAssistantResponse(rawResponse)
        let responseText = parsed.displayText.isEmpty ? rawResponse : parsed.displayText

        if result.exitCode != 0 {
            let message = stderrText.isEmpty ? "Agent execution failed with exit code \(result.exitCode)" : stderrText
            throw NSError(
                domain: "ExternalAgentExecutionService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildPrompt(userText: String) -> String {
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
              let decoded = try? JSONDecoder().decode(ExternalTaskProposalPayload.self, from: data) else {
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
}

private struct ExternalTaskProposalPayload: Decodable {
    var title: String
    var instructions: String
    var scheduleType: TaskScheduleType
    var scheduleValue: String
    var runtimeMode: RuntimeMode
    var externalDirectory: String?
    var repoPath: String?
    var runNow: Bool
}
