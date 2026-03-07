import Foundation
import Combine

enum ChatSessionEvent {
    case assistantDelta(String)
    case stderr(String)
    case proposal(TaskProposal)
    case browserRequested
    case completed
    case failed(String)
}

final class ChatSessionService {
    private let sessionStore: AssistantSessionStore
    private let personaManager: PersonaManager
    private let runtime: CodexRuntime
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let browserAutomationService: BrowserAutomationService
    private let activityLogStore: ActivityLogStore

    private let stateLock = NSLock()
    private var continuation: AsyncStream<ChatSessionEvent>.Continuation?

    init(
        sessionStore: AssistantSessionStore,
        personaManager: PersonaManager,
        runtime: CodexRuntime,
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore,
        browserAutomationService: BrowserAutomationService,
        activityLogStore: ActivityLogStore
    ) {
        self.sessionStore = sessionStore
        self.personaManager = personaManager
        self.runtime = runtime
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
        self.browserAutomationService = browserAutomationService
        self.activityLogStore = activityLogStore
    }

    var pendingBrowserConfirmationPublisher: AnyPublisher<BrowserConfirmationRecord?, Never> {
        browserAutomationService.$pendingConfirmation.eraseToAnyPublisher()
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
        var session = try loadDefaultSession()

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

        var prompt = buildChatPrompt(userText: text)

        for _ in 0..<12 {
            let execution = try await executePrompt(prompt, session: session, launchConfig: launchConfig)
            session = execution.session
            let parsed = parseAssistantResponse(execution.stdout)

            if !parsed.displayText.isEmpty {
                try appendMessage(role: .assistant, text: parsed.displayText, source: .codexStdout)
            }

            if let proposal = parsed.proposal {
                emit(.proposal(proposal))
            }

            if execution.result.exitCode != 0 {
                let message = execution.stderr.isEmpty ? "Chat failed with exit code \(execution.result.exitCode)" : execution.stderr
                emit(.failed(message))
                return
            }

            if let browserCommand = parsed.browserCommand {
                emit(.browserRequested)
                let browserResult = try await executeBrowserToolCommand(browserCommand)
                prompt = buildBrowserToolResultPrompt(from: browserResult)
                continue
            }

            emit(.completed)
            return
        }

        emit(.failed("Browser tool loop exceeded the maximum number of steps"))
    }

    @MainActor
    func sendBrowserCommand(_ command: BrowserAgentCommand) async throws -> BrowserAgentResult {
        switch command {
        case let .inspect(sessionID):
            let snapshot = try await browserAutomationService.inspectPage(sessionID: sessionID)
            let result = BrowserAgentResult(
                kind: .inspection,
                summary: inspectionSummary(snapshot),
                snapshot: snapshot,
                confirmation: nil
            )
            try appendBrowserMessage(result.summary)
            try appendActivity(kind: .browserAutomation, message: result.summary)
            return result

        case let .execute(sessionID, profileId, action):
            do {
                try await browserAutomationService.execute(action, sessionID: sessionID, profileId: profileId)
                let snapshot = try? await browserAutomationService.inspectPage(sessionID: sessionID)
                let result = BrowserAgentResult(
                    kind: .actionExecuted,
                    summary: actionSummary(action, snapshot: snapshot),
                    snapshot: snapshot,
                    confirmation: nil
                )
                try appendBrowserMessage(result.summary)
                try appendActivity(kind: .browserAutomation, message: result.summary)
                return result
            } catch BrowserPolicyEnforcerError.confirmationRequired {
                let confirmation = browserAutomationService.pendingConfirmation
                let result = BrowserAgentResult(
                    kind: .confirmationRequired,
                    summary: confirmationSummary(confirmation),
                    snapshot: nil,
                    confirmation: confirmation
                )
                try appendBrowserMessage(result.summary)
                try appendActivity(kind: .browserConfirmationRequired, message: result.summary)
                return result
            }

        case let .resolveConfirmation(sessionID, resolution):
            try browserAutomationService.resolveConfirmation(sessionID: sessionID, resolution: resolution)
            let result = BrowserAgentResult(
                kind: .confirmationResolved,
                summary: resolutionSummary(resolution),
                snapshot: nil,
                confirmation: browserAutomationService.pendingConfirmation
            )
            try appendBrowserMessage(result.summary)
            try appendActivity(kind: .browserAutomation, message: result.summary)
            return result
        }
    }

    func appendAssistantMessage(_ text: String) throws {
        try appendMessage(role: .assistant, text: text, source: .codexStdout)
    }

    private func buildChatPrompt(userText: String) -> String {
        """
        FORMAT INSTRUCTION:
        If and only if the user is clearly asking to create a recurring or background task, append exactly one XML block at the end of your response:
        <agenthub_task_proposal>{"title":"...","instructions":"...","scheduleType":"manual|intervalMinutes|dailyAtHHMM","scheduleValue":"...","runtimeMode":"chatOnly|task","repoPath":null,"runNow":false}</agenthub_task_proposal>
        If you need to operate the in-app browser, append exactly one XML block at the end of your response:
        <agenthub_browser_command>{"operation":"inspect_page|open_url|go_back|go_forward|reload|click|fill|select|submit|resolve_confirmation","url":"...","targetId":"...","value":"...","resolution":"approve|reject|takeOver"}</agenthub_browser_command>
        Use browser commands one step at a time. Inspect the page first, then choose the next bounded action based on the returned actionable elements.
        Do not ask the user for CSS selectors. Use only the provided target IDs from page inspection.
        Do not mention the XML block in your prose.
        Do not restate or override instructions already provided by AGENTS.md.

        BROWSER CONTEXT:
        \(browserContextSummary())

        USER:
        \(userText)
        """
    }

    private func parseAssistantResponse(_ text: String) -> (displayText: String, proposal: TaskProposal?, browserCommand: ParsedBrowserCommand?) {
        var stripped = text
        var proposal: TaskProposal?
        var browserCommand: ParsedBrowserCommand?

        if let match = firstMatch(in: stripped, pattern: #"<agenthub_task_proposal>([\s\S]*?)</agenthub_task_proposal>"#) {
            if let data = match.payload.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(TaskProposalPayload.self, from: data) {
                proposal = TaskProposal(
                    id: UUID(),
                    title: decoded.title,
                    instructions: decoded.instructions,
                    scheduleType: decoded.scheduleType,
                    scheduleValue: decoded.scheduleValue,
                    runtimeMode: decoded.runtimeMode,
                    repoPath: decoded.externalDirectory ?? decoded.repoPath,
                    runNow: decoded.runNow
                )
            }
            stripped = match.stripped
        }

        if let match = firstMatch(in: stripped, pattern: #"<agenthub_browser_command>([\s\S]*?)</agenthub_browser_command>"#) {
            if let data = match.payload.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ParsedBrowserCommand.self, from: data) {
                browserCommand = decoded
            }
            stripped = match.stripped
        }

        return (stripped.trimmingCharacters(in: .whitespacesAndNewlines), proposal, browserCommand)
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

    private func appendBrowserMessage(_ text: String) throws {
        try appendMessage(role: .system, text: text, source: .browserSystemEvent)
    }

    private func appendMessage(role: MessageRole, text: String, source: MessageSource) throws {
        let session = try loadDefaultSession()
        let message = Message(
            id: UUID(),
            sessionId: session.id,
            role: role,
            text: text,
            source: source,
            createdAt: Date()
        )
        try sessionStore.appendMessage(message)
    }

    private func appendActivity(kind: ActivityKind, message: String) throws {
        try activityLogStore.append(
            ActivityEvent(
                id: UUID(),
                taskId: nil,
                kind: kind,
                message: message,
                createdAt: Date()
            )
        )
    }

    private func loadDefaultSession() throws -> AssistantSession {
        let persona = try personaManager.defaultPersona()
        return try sessionStore.loadOrCreateDefault(personaId: persona.id)
    }

    private func executePrompt(
        _ prompt: String,
        session: AssistantSession,
        launchConfig: CodexLaunchConfig
    ) async throws -> (result: CodexExecutionResult, stdout: String, stderr: String, session: AssistantSession) {
        let runtimeStream = runtime.streamEvents()
        var assistantText = ""
        var stderrText = ""
        var updatedSession = session

        let bridgeTask = Task {
            for await event in runtimeStream {
                switch event {
                case let .stdoutLine(line):
                    assistantText += assistantText.isEmpty ? line : "\n\(line)"
                    if !shouldSuppressStreamingLine(line) {
                        emit(.assistantDelta(line))
                    }
                case let .stderrLine(line):
                    stderrText += stderrText.isEmpty ? line : "\n\(line)"
                    emit(.stderr(line))
                case let .threadIdentified(threadId):
                    updatedSession.codexThreadId = threadId
                    updatedSession.updatedAt = Date()
                    try? sessionStore.save(updatedSession)
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
                updatedSession.codexThreadId = threadId
            }
        }

        _ = await bridgeTask.result
        updatedSession.updatedAt = Date()
        try sessionStore.save(updatedSession)
        return (result, assistantText, stderrText, updatedSession)
    }

    @MainActor
    private func executeBrowserToolCommand(_ command: ParsedBrowserCommand) async throws -> BrowserAgentResult {
        guard let session = browserAutomationService.activeSession else {
            throw BrowserAutomationSessionError.sessionUnavailable
        }

        emit(.browserRequested)
        browserAutomationService.setMode(.agentControlling, sessionID: session.record.id)
        try await waitForAttachedBrowser(sessionID: session.record.id)

        let browserCommand: BrowserAgentCommand
        switch command.operation {
        case .inspectPage:
            browserCommand = .inspect(sessionID: session.record.id)
        case .openURL:
            guard let urlString = command.url, let url = URL(string: urlString) else {
                throw BrowserAutomationSessionError.scriptExecutionFailed
            }
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .open(url))
        case .goBack:
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .goBack)
        case .goForward:
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .goForward)
        case .reload:
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .reload)
        case .click:
            guard let targetId = command.targetId else { throw BrowserAutomationSessionError.targetNotFound("<missing>") }
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .click(targetID: targetId))
        case .fill:
            guard let targetId = command.targetId else { throw BrowserAutomationSessionError.targetNotFound("<missing>") }
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .fill(targetID: targetId, value: command.value ?? ""))
        case .select:
            guard let targetId = command.targetId else { throw BrowserAutomationSessionError.targetNotFound("<missing>") }
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .select(targetID: targetId, value: command.value ?? ""))
        case .submit:
            guard let targetId = command.targetId else { throw BrowserAutomationSessionError.targetNotFound("<missing>") }
            browserCommand = .execute(sessionID: session.record.id, profileId: session.profile.profileId, action: .submit(targetID: targetId))
        case .resolveConfirmation:
            let resolution = switch command.resolution {
            case .approve?:
                BrowserConfirmationResolution.approved
            case .reject?:
                BrowserConfirmationResolution.rejected
            case .takeOver?:
                BrowserConfirmationResolution.takeOver
            case nil:
                BrowserConfirmationResolution.pending
            }
            browserCommand = .resolveConfirmation(sessionID: session.record.id, resolution: resolution)
        }

        return try await sendBrowserCommand(browserCommand)
    }

    private func buildBrowserToolResultPrompt(from result: BrowserAgentResult) -> String {
        """
        BROWSER TOOL RESULT:
        \(serializeBrowserResult(result))

        Continue the conversation. If you need another browser step, emit exactly one <agenthub_browser_command> block at the end of your response. Otherwise answer the user normally.
        """
    }

    private func serializeBrowserResult(_ result: BrowserAgentResult) -> String {
        var payload: [String: Any] = [
            "kind": String(describing: result.kind),
            "summary": result.summary
        ]
        if let snapshot = result.snapshot {
            payload["snapshot"] = [
                "currentURL": snapshot.currentURL ?? "",
                "title": snapshot.title,
                "isLoading": snapshot.isLoading,
                "visibleTextSummary": snapshot.visibleTextSummary,
                "actionableElements": snapshot.actionableElements.map {
                    [
                        "id": $0.id,
                        "role": $0.role.rawValue,
                        "label": $0.label,
                        "disabled": $0.disabled,
                        "hidden": $0.hidden
                    ]
                }
            ]
        }
        if let confirmation = result.confirmation {
            payload["confirmation"] = [
                "actionType": confirmation.actionType.rawValue,
                "target": confirmation.target ?? "",
                "currentURL": confirmation.currentURL ?? "",
                "pageTitle": confirmation.pageTitle
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return result.summary
        }
        return string
    }

    private func browserContextSummary() -> String {
        guard let session = browserAutomationService.activeSession else {
            return "No active browser session."
        }
        return "Profile \(session.profile.displayName), mode \(session.mode.rawValue), current URL \(session.record.currentURL ?? "none")."
    }

    private func waitForAttachedBrowser(sessionID: UUID) async throws {
        for _ in 0..<20 {
            if let session = browserAutomationService.activeSession,
               session.record.id == sessionID,
               session.isWebViewAttached {
                return
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw BrowserAutomationSessionError.webViewUnavailable
    }

    private func shouldSuppressStreamingLine(_ line: String) -> Bool {
        line.contains("<agenthub_task_proposal>") || line.contains("<agenthub_browser_command>")
    }

    private func firstMatch(in text: String, pattern: String) -> (payload: String, stripped: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let payloadRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return (
            payload: String(text[payloadRange]),
            stripped: text.replacingCharacters(in: fullRange, with: "")
        )
    }

    private func inspectionSummary(_ snapshot: BrowserPageSnapshot) -> String {
        let labels = snapshot.actionableElements
            .prefix(3)
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let labelSummary = labels.isEmpty ? "No obvious actions found yet." : "Top actions: \(labels)."
        return "Browser inspected \(snapshot.title.isEmpty ? "current page" : snapshot.title) at \(snapshot.currentURL ?? "unknown URL"). \(labelSummary)"
    }

    private func actionSummary(_ action: BrowserAutomationAction, snapshot: BrowserPageSnapshot?) -> String {
        let destination = snapshot?.currentURL ?? browserAutomationService.activeSession?.record.currentURL ?? "unknown URL"
        switch action {
        case let .open(url):
            return "Opened \(url.absoluteString) in the active browser session."
        case .goBack:
            return "Moved back in the active browser session. Current page: \(destination)."
        case .goForward:
            return "Moved forward in the active browser session. Current page: \(destination)."
        case .reload:
            return "Reloaded the active browser page at \(destination)."
        case let .click(targetID):
            return "Clicked browser target \(targetID). Current page: \(destination)."
        case let .fill(targetID, value):
            return "Filled browser target \(targetID) with “\(value)”. Current page: \(destination)."
        case let .select(targetID, value):
            return "Selected “\(value)” in browser target \(targetID). Current page: \(destination)."
        case let .submit(targetID):
            return "Submitted browser target \(targetID). Current page: \(destination)."
        }
    }

    private func confirmationSummary(_ confirmation: BrowserConfirmationRecord?) -> String {
        guard let confirmation else {
            return "Browser action requires confirmation before it can continue."
        }
        let target = confirmation.target.map { " on \($0)" } ?? ""
        let page = confirmation.currentURL ?? "unknown URL"
        return "Browser action \(confirmation.actionType.rawValue)\(target) is waiting for confirmation on \(page)."
    }

    private func resolutionSummary(_ resolution: BrowserConfirmationResolution) -> String {
        switch resolution {
        case .approved:
            return "Browser confirmation approved. The agent can continue with the current step."
        case .rejected:
            return "Browser confirmation rejected. The agent will not continue that step."
        case .takeOver:
            return "Browser control switched to manual takeover."
        case .pending:
            return "Browser confirmation is still pending."
        }
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

private struct ParsedBrowserCommand: Decodable {
    var operation: BrowserToolOperation
    var url: String?
    var targetId: String?
    var value: String?
    var resolution: BrowserToolResolution?
}

private enum BrowserToolOperation: String, Decodable {
    case inspectPage = "inspect_page"
    case openURL = "open_url"
    case goBack = "go_back"
    case goForward = "go_forward"
    case reload
    case click
    case fill
    case select
    case submit
    case resolveConfirmation = "resolve_confirmation"
}

private enum BrowserToolResolution: String, Decodable {
    case approve
    case reject
    case takeOver
}
