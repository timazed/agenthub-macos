import Foundation

enum ChatSessionEvent {
    case assistantDelta(String)
    case stderr(String)
    case proposal(TaskProposal)
    case completed
    case failed(String)
}

struct ChatBrowserIntent: Equatable {
    enum Kind: Equatable {
        case openTableRestaurantSearch
    }

    let kind: Kind
    let request: ChromiumRestaurantSearchRequest
    let bookingRequested: Bool

    nonisolated static func parse(_ text: String) -> ChatBrowserIntent? {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()
        guard lowered.contains("opentable") || lowered.contains("open table") else {
            return nil
        }

        let bookingRequested = ["reservation", "reserve", "book", "booking"].contains { lowered.contains($0) }
        let segments = normalized
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let venueAndLocation = extractVenueAndLocation(from: segments, fullText: normalized)
        guard let venueName = venueAndLocation.venueName, !venueName.isEmpty else {
            return nil
        }

        let locationHint = venueAndLocation.locationHint
        let query = [venueName, locationHint]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")

        return ChatBrowserIntent(
            kind: .openTableRestaurantSearch,
            request: ChromiumRestaurantSearchRequest(
                siteURL: "https://www.opentable.com",
                query: query,
                venueName: venueName,
                locationHint: locationHint
            ),
            bookingRequested: bookingRequested
        )
    }

    private nonisolated static func extractVenueAndLocation(from segments: [String], fullText: String) -> (venueName: String?, locationHint: String?) {
        var cleanedSegments = segments
            .map(cleanSegment)
            .filter { !$0.isEmpty }

        if cleanedSegments.isEmpty {
            cleanedSegments = [cleanSegment(fullText)].filter { !$0.isEmpty }
        }

        let venueName = cleanedSegments.first
        let locationHint = cleanedSegments.dropFirst().first
        return (venueName, locationHint)
    }

    private nonisolated static func cleanSegment(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let removalPatterns = [
            #"(?i)\bopen\s*table\b"#,
            #"(?i)\bmake\s+a\s+reservation\s+for\s+me\b"#,
            #"(?i)\bbook\s+(?:me\s+)?(?:a\s+)?reservation\b"#,
            #"(?i)\bnavigate\s+to\b"#,
            #"(?i)\bopen\b"#,
            #"(?i)\bfind\b"#,
            #"(?i)\bshow\s+me\b"#,
            #"(?i)\bgo\s+to\b"#,
            #"(?i)\bpage\b"#,
            #"(?i)\bfor\s+me\b"#,
            #"(?i)\bon\b$"#
        ]

        for pattern in removalPatterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        value = value
            .replacingOccurrences(of: #"(?i)\bthe\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\s+people\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\s*(?:am|pm)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:today|tomorrow)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d{1,2}(?:st|nd|rd|th)?\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-").union(.whitespacesAndNewlines))

        let lowered = value.lowercased()
        if lowered.isEmpty {
            return ""
        }
        if ["on", "at", "for"].contains(lowered) {
            return ""
        }
        if lowered.contains("reservation") || lowered.contains("book") {
            return ""
        }
        if lowered == "opentable" || lowered == "open table" {
            return ""
        }
        return value
    }
}

final class ChatSessionService {
    private let sessionStore: AssistantSessionStore
    private let personaManager: PersonaManager
    private let runtime: CodexRuntime
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let browserControllerProvider: @MainActor () -> ChromiumBrowserController

    private let stateLock = NSLock()
    private nonisolated(unsafe) var continuation: AsyncStream<ChatSessionEvent>.Continuation?

    init(
        sessionStore: AssistantSessionStore,
        personaManager: PersonaManager,
        runtime: CodexRuntime,
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore,
        browserControllerProvider: @escaping @MainActor () -> ChromiumBrowserController
    ) {
        self.sessionStore = sessionStore
        self.personaManager = personaManager
        self.runtime = runtime
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
        self.browserControllerProvider = browserControllerProvider
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

        if let browserIntent = ChatBrowserIntent.parse(text) {
            try await handleBrowserIntent(browserIntent, session: &session)
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

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

    private func handleBrowserIntent(_ intent: ChatBrowserIntent, session: inout AssistantSession) async throws {
        let browserController = await MainActor.run { browserControllerProvider() }
        emit(.assistantDelta("Using the embedded Chromium browser to search OpenTable for \(intent.request.venueName)."))

        let result = try await browserController.runRestaurantSearchFlow(request: intent.request) { [weak self] message in
            self?.emit(.assistantDelta(message))
        }

        let finalText: String
        if intent.bookingRequested {
            finalText = """
            I opened the exact OpenTable page for \(result.venueName)\(formattedLocationSuffix(result.locationHint)) in the embedded Chromium browser. This chat path is now using the Chromium controller for the venue search and page navigation; reservation selection itself still needs a dedicated controller step on top of the restaurant page.
            """
        } else {
            finalText = """
            I opened the exact OpenTable page for \(result.venueName)\(formattedLocationSuffix(result.locationHint)) in the embedded Chromium browser.
            """
        }

        let assistantMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            text: finalText,
            source: .codexStdout,
            createdAt: Date()
        )
        try sessionStore.appendMessage(assistantMessage)
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

    private func formattedLocationSuffix(_ locationHint: String?) -> String {
        guard let locationHint,
              !locationHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return " in \(locationHint)"
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
