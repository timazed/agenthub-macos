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
    let bookingParameters: ChromiumRestaurantBookingParameters

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
            bookingRequested: bookingRequested,
            bookingParameters: extractBookingParameters(from: lowered)
        )
    }

    private nonisolated static func extractBookingParameters(from loweredText: String) -> ChromiumRestaurantBookingParameters {
        let partySize = firstMatch(
            in: loweredText,
            patterns: [
                #"party of (\d+)"#,
                #"for (\d+) people"#,
                #"(\d+) people"#
            ]
        ).flatMap(Int.init)

        let timeText = firstMatch(
            in: loweredText,
            patterns: [
                #"\b(\d{1,2}(?::\d{2})?\s?(?:am|pm))\b"#,
                #"\bat (\d{1,2}(?::\d{2})?\s?(?:am|pm))\b"#
            ]
        )

        let dateText = firstMatch(
            in: loweredText,
            patterns: [
                #"\b(today|tomorrow)\b"#,
                #"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?\s+\d{1,2}(?:st|nd|rd|th)?)\b"#
            ]
        )

        return ChromiumRestaurantBookingParameters(
            dateText: dateText,
            timeText: timeText,
            partySize: partySize
        )
    }

    private nonisolated static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let captureRange = Range(match.range(at: captureIndex), in: text) else { continue }
            let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
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

struct GenericBrowserChatIntent: Equatable {
    let goalText: String
    let initialURL: String?

    nonisolated static func parse(_ text: String) -> GenericBrowserChatIntent? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let explicitURL = extractURL(from: normalized) {
            return GenericBrowserChatIntent(goalText: normalized, initialURL: normalizeURL(explicitURL))
        }

        let lowered = normalized.lowercased()
        let knownSites: [(needle: String, url: String)] = [
            ("opentable", "https://www.opentable.com"),
            ("booking.com", "https://www.booking.com"),
            ("expedia", "https://www.expedia.com"),
            ("kayak", "https://www.kayak.com"),
            ("google flights", "https://www.google.com/travel/flights"),
            ("airbnb", "https://www.airbnb.com"),
            ("amazon", "https://www.amazon.com")
        ]
        if let site = knownSites.first(where: { lowered.contains($0.needle) }) {
            return GenericBrowserChatIntent(goalText: normalized, initialURL: site.url)
        }

        let browserVerbs = ["open", "browse", "book", "find", "search", "look up", "go to", "navigate"]
        guard browserVerbs.contains(where: { lowered.contains($0) }) else {
            return nil
        }

        return GenericBrowserChatIntent(goalText: normalized, initialURL: nil)
    }

    private nonisolated static func extractURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector.firstMatch(in: text, options: [], range: range)
        return match?.url?.absoluteString
    }

    private nonisolated static func normalizeURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawValue }

        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme) else {
            return withScheme
        }
        if components.scheme == nil {
            components.scheme = "https"
        }
        if let host = components.host?.lowercased() {
            switch host {
            case "booking.com", "www.booking.com":
                components.scheme = "https"
                components.host = "www.booking.com"
            case "opentable.com", "www.opentable.com":
                components.scheme = "https"
                components.host = "www.opentable.com"
            default:
                break
            }
        }
        return components.string ?? withScheme
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

        if let genericBrowserIntent = GenericBrowserChatIntent.parse(text) {
            _ = try await handleGenericBrowserIntent(genericBrowserIntent, persona: persona, session: &session)
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

    func runBrowserScenario(_ scenario: BrowserSmokeScenarioDefinition) async throws -> BrowserScenarioRunSummary {
        defer { finishStream() }

        let persona = try personaManager.defaultPersona()
        var session = AssistantSession(
            id: UUID(),
            codexThreadId: nil,
            personaId: persona.id,
            mode: .chatOnly,
            createdAt: Date(),
            updatedAt: Date()
        )
        let metadata = BrowserScenarioMetadata(
            id: scenario.id,
            title: scenario.title,
            category: scenario.category
        )

        emit(.assistantDelta("Running browser smoke scenario \(scenario.id) (\(scenario.category))."))

        if let browserIntent = ChatBrowserIntent.parse(scenario.goalText) {
            let summary = try await handleBrowserIntent(
                browserIntent,
                session: &session,
                persistMessages: false,
                scenarioMetadata: metadata
            )
            emit(.completed)
            return BrowserScenarioRunSummary(
                scenarioID: scenario.id,
                category: scenario.category,
                outcome: browserIntent.bookingRequested && browserIntent.bookingParameters.isSpecified
                    ? "stopped_at_confirmation_boundary"
                    : "completed",
                finalSummary: summary
            )
        }

        if let genericBrowserIntent = GenericBrowserChatIntent.parse(scenario.goalText) {
            let result = try await handleGenericBrowserIntent(
                genericBrowserIntent,
                persona: persona,
                session: &session,
                persistMessages: false,
                scenarioMetadata: metadata
            )
            emit(.completed)
            return BrowserScenarioRunSummary(
                scenarioID: scenario.id,
                category: scenario.category,
                outcome: result.outcome,
                finalSummary: result.finalSummary
            )
        }

        throw ChromiumBrowserActionError(message: "Scenario \(scenario.id) does not parse into a browser intent.")
    }

    @discardableResult
    private func handleBrowserIntent(
        _ intent: ChatBrowserIntent,
        session: inout AssistantSession,
        persistMessages: Bool = true,
        scenarioMetadata: BrowserScenarioMetadata? = nil
    ) async throws -> String {
        let browserController = await MainActor.run { browserControllerProvider() }
        emit(.assistantDelta("Using the embedded Chromium browser to search OpenTable for \(intent.request.venueName)."))

        let finalText: String
        let outcome: String
        if intent.bookingRequested, intent.bookingParameters.isSpecified {
            let result = try await browserController.runRestaurantBookingFlow(
                request: ChromiumRestaurantBookingRequest(
                    searchRequest: intent.request,
                    parameters: intent.bookingParameters
                )
            ) { [weak self] message in
                self?.emit(.assistantDelta(message))
            }
            let slotText = result.selectedSlot ?? "an available slot"
            finalText = """
            I navigated to the OpenTable venue page for \(result.venueName) and selected \(slotText). I stopped before the final reserve or confirm action, so approval is still required for the last transactional step.
            """
            outcome = "stopped_at_confirmation_boundary"
        } else {
            let result = try await browserController.runRestaurantSearchFlow(request: intent.request) { [weak self] message in
                self?.emit(.assistantDelta(message))
            }
            finalText = """
            I opened the exact OpenTable page for \(result.venueName)\(formattedLocationSuffix(result.locationHint)) in the embedded Chromium browser.
            """
            outcome = "completed"
        }

        try await persistBrowserRunArtifacts(
            outcome: outcome,
            goalText: intent.request.query,
            initialURL: intent.request.siteURL,
            session: session,
            controller: browserController,
            inspectionHistory: await MainActor.run { browserController.browserDebugArtifacts().lastInspection.map { [$0] } ?? [] },
            recentHistory: [],
            finalSummary: finalText,
            scenarioMetadata: scenarioMetadata
        )
        try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
        return finalText
    }

    private func handleGenericBrowserIntent(
        _ intent: GenericBrowserChatIntent,
        persona: Persona,
        session: inout AssistantSession,
        persistMessages: Bool = true,
        scenarioMetadata: BrowserScenarioMetadata? = nil
    ) async throws -> BrowserScenarioRunSummary {
        let browserController = await MainActor.run { browserControllerProvider() }
        emit(.assistantDelta("Using the embedded Chromium browser for this web task."))

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

        var lastResultSummary = intent.initialURL != nil
            ? "The browser can open \(intent.initialURL!)."
            : "No browser action has run yet."
        var latestInspection: ChromiumInspection?
        var inspectionHistory: [ChromiumInspection] = []
        var recentHistory: [String] = []
        var actionSignatureCounts: [String: Int] = [:]
        var lastProgressSnapshot: BrowserProgressSnapshot?
        var stalledStepCount = 0
        var recoveryCount = 0
        let maxSteps = 12
        func recordInspection(_ inspection: ChromiumInspection?) {
            guard let inspection else { return }
            inspectionHistory.append(inspection)
            if inspectionHistory.count > 20 {
                inspectionHistory.removeFirst(inspectionHistory.count - 20)
            }
        }

        do {
            for step in 1...maxSteps {
                let state = await MainActor.run { browserController.browserSnapshot() }
                let prompt = buildBrowserAgentPrompt(
                    goalText: intent.goalText,
                    initialURL: intent.initialURL,
                    state: state,
                    inspection: latestInspection,
                    lastResultSummary: lastResultSummary,
                    recentHistory: recentHistory,
                    step: step,
                    maxSteps: maxSteps
                )

                let turn = try await performCodexTurn(
                    prompt: prompt,
                    session: &session,
                    config: launchConfig,
                    forwardAssistantLines: false
                )

                if turn.result.exitCode != 0 {
                    let message = turn.stderrText.isEmpty
                        ? "Browser agent turn failed with exit code \(turn.result.exitCode)"
                        : turn.stderrText
                    throw ChromiumBrowserActionError(message: message)
                }

                let parsed = parseBrowserAssistantResponse(turn.assistantText)
                if !parsed.displayText.isEmpty {
                    emit(.assistantDelta(parsed.displayText))
                }

                guard let command = parsed.command else {
                    throw ChromiumBrowserActionError(message: "Codex did not return a browser command.")
                }

                let signature = browserActionSignature(command, url: state.urlString)
                actionSignatureCounts[signature, default: 0] += 1
                if actionSignatureCounts[signature, default: 0] >= 3 {
                    let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
                    latestInspection = refreshedInspection
                    recordInspection(refreshedInspection)
                    lastResultSummary = browserRecoverySummary(
                        for: command,
                        message: "The same action repeated without changing the page.",
                        inspection: refreshedInspection,
                        progressChanged: false
                    )
                    recentHistory.append("Recovery: repeated \(command.action.rawValue) without progress.")
                    emit(.assistantDelta(lastResultSummary))
                    actionSignatureCounts[signature] = 0
                    stalledStepCount = 0
                    recoveryCount += 1
                    if recoveryCount >= 4 {
                        throw ChromiumBrowserActionError(message: "Browser agent is stuck on stale targets and repeated replans.")
                    }
                    continue
                }

                if command.action == .done {
                    let finalText = parsed.displayText.isEmpty
                        ? (command.finalResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Finished the browser task.")
                        : parsed.displayText
                    try await persistBrowserRunArtifacts(
                        outcome: "completed",
                        goalText: intent.goalText,
                        initialURL: intent.initialURL,
                        session: session,
                        controller: browserController,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        finalSummary: finalText,
                        scenarioMetadata: scenarioMetadata
                    )
                    try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                    return BrowserScenarioRunSummary(
                        scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                        category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                        outcome: "completed",
                        finalSummary: finalText
                    )
                }

                let previousProgressSnapshot = browserProgressSnapshot(state: state, inspection: latestInspection)
                let execution: BrowserAgentExecutionResult
                do {
                    execution = try await executeBrowserAgentCommand(command, inspection: latestInspection, controller: browserController)
                } catch {
                    let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                    guard isRecoverableBrowserError(message) else {
                        throw error
                    }
                    let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
                    recordInspection(refreshedInspection)
                    if let recoveredExecution = try await retryBrowserAgentCommandIfPossible(
                        command,
                        staleInspection: latestInspection,
                        refreshedInspection: refreshedInspection,
                        controller: browserController
                    ) {
                        latestInspection = recoveredExecution.inspection ?? refreshedInspection
                        recordInspection(latestInspection)
                        lastResultSummary = recoveredExecution.summary
                        recentHistory.append("Recovery: \(command.action.rawValue) -> \(recoveredExecution.summary)")
                        if recentHistory.count > 6 {
                            recentHistory.removeFirst(recentHistory.count - 6)
                        }
                        emit(.assistantDelta(recoveredExecution.summary))
                        let recoveredState = await MainActor.run { browserController.browserSnapshot() }
                        lastProgressSnapshot = browserProgressSnapshot(state: recoveredState, inspection: latestInspection)
                        stalledStepCount = 0
                        recoveryCount += 1
                        continue
                    }
                    latestInspection = refreshedInspection
                    let currentState = await MainActor.run { browserController.browserSnapshot() }
                    let refreshedProgressSnapshot = browserProgressSnapshot(state: currentState, inspection: refreshedInspection)
                    lastResultSummary = browserRecoverySummary(
                        for: command,
                        message: message,
                        inspection: refreshedInspection,
                        progressChanged: refreshedProgressSnapshot != previousProgressSnapshot
                    )
                    recentHistory.append("Recovery: \(command.action.rawValue) -> \(message)")
                    emit(.assistantDelta(lastResultSummary))
                    stalledStepCount = 0
                    recoveryCount += 1
                    if recoveryCount >= 4 {
                        throw ChromiumBrowserActionError(message: "Browser agent exceeded the recovery budget while trying to re-target the page.")
                    }
                    continue
                }

                latestInspection = execution.inspection ?? latestInspection
                recordInspection(latestInspection)
                lastResultSummary = execution.summary
                recentHistory.append("Step \(step): \(command.action.rawValue) -> \(execution.summary)")
                if recentHistory.count > 6 {
                    recentHistory.removeFirst(recentHistory.count - 6)
                }
                emit(.assistantDelta(execution.summary))

                if let stopReason = BrowserTransactionalGuard.stopReason(goalText: intent.goalText, inspection: latestInspection) {
                    let finalText = "\(stopReason) Approval is still required for any final transaction step."
                    try await persistBrowserRunArtifacts(
                        outcome: "stopped_at_confirmation_boundary",
                        goalText: intent.goalText,
                        initialURL: intent.initialURL,
                        session: session,
                        controller: browserController,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        finalSummary: finalText,
                        scenarioMetadata: scenarioMetadata
                    )
                    try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                    return BrowserScenarioRunSummary(
                        scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                        category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                        outcome: "stopped_at_confirmation_boundary",
                        finalSummary: finalText
                    )
                }

                let currentState = await MainActor.run { browserController.browserSnapshot() }
                let progressSnapshot = browserProgressSnapshot(state: currentState, inspection: latestInspection)
                if progressSnapshot == lastProgressSnapshot && command.action != .inspectPage {
                    stalledStepCount += 1
                } else {
                    stalledStepCount = 0
                    recoveryCount = 0
                }
                lastProgressSnapshot = progressSnapshot

                if stalledStepCount >= 2 {
                    let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
                    latestInspection = refreshedInspection
                    recordInspection(refreshedInspection)
                    lastResultSummary = browserRecoverySummary(
                        for: command,
                        message: "The last actions did not visibly change the page state.",
                        inspection: refreshedInspection,
                        progressChanged: false
                    )
                    recentHistory.append("Recovery: refreshed inspection after stalled browser progress.")
                    emit(.assistantDelta(lastResultSummary))
                    stalledStepCount = 0
                    recoveryCount += 1
                    if recoveryCount >= 4 {
                        throw ChromiumBrowserActionError(message: "Browser agent exceeded the recovery budget after repeated stalled steps.")
                    }
                }
            }

            throw ChromiumBrowserActionError(message: "Browser agent loop exceeded the maximum number of steps.")
        } catch {
            let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
            try await persistBrowserRunArtifacts(
                outcome: "failed",
                goalText: intent.goalText,
                initialURL: intent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: message,
                scenarioMetadata: scenarioMetadata
            )
            emit(.failed(message))
            throw error
        }
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

    private func buildBrowserAgentPrompt(
        goalText: String,
        initialURL: String?,
        state: ChromiumBrowserState,
        inspection: ChromiumInspection?,
        lastResultSummary: String,
        recentHistory: [String],
        step: Int,
        maxSteps: Int
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stateJSON = (try? encoder.encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let inspectionJSON = inspection.map(encodeJSON(_:)) ?? "null"
        let initialURLLine = initialURL.map { "Initial URL hint: \($0)" } ?? "Initial URL hint: none"
        let historySection = recentHistory.isEmpty
            ? "Recent browser history:\n- none yet"
            : "Recent browser history:\n- " + recentHistory.joined(separator: "\n- ")

        return """
        You are controlling an embedded Chromium browser inside AgentHub.

        Goal:
        \(goalText)

        Step \(step) of \(maxSteps)
        \(initialURLLine)

        Last browser result:
        \(lastResultSummary)

        \(historySection)

        Current browser state JSON:
        \(stateJSON)

        Latest page inspection JSON:
        \(inspectionJSON)

        Rules:
        - Choose exactly one next browser action.
        - Prefer semantic structures from the inspection JSON first:
          - semanticTargets
          - forms
          - controlGroups
          - autocompleteSurfaces
          - datePickers
          - resultLists
          - cards
          - dialogs
          - transactionalBoundaries
        - Use selectors from the inspection JSON when needed, but do not rely on raw selectors if a semantic target is available.
        - When you use a raw selector action, also include label when you know the semantic target so runtime recovery has a stable target name.
        - If you do not have enough page information, use inspect_page.
        - Never mention shell commands, files, local tools, or external browsers.
        - Do not ask the user to click controls that you can operate yourself.
        - If the goal is complete, return action done with a finalResponse.
        - Keep any prose outside the command brief.

        Allowed actions:
        - inspect_page
        - open_url
        - click_selector
        - click_text
        - type_text
        - select_option
        - choose_autocomplete_option
        - choose_grouped_option
        - pick_date
        - submit_form
        - press_key
        - scroll
        - wait_for_text
        - wait_for_selector
        - wait_for_navigation
        - wait_for_results
        - wait_for_dialog
        - wait_for_settle
        - capture_snapshot
        - done

        Emit exactly one XML block at the end of your response:
        <agenthub_browser_command>{"action":"inspect_page","selector":null,"text":null,"url":null,"key":null,"timeoutSeconds":null,"deltaY":null,"label":null,"finalResponse":null,"rationale":"..."}</agenthub_browser_command>
        """
    }

    private func parseBrowserAssistantResponse(_ text: String) -> (displayText: String, command: BrowserAgentCommand?) {
        BrowserAgentResponseParser.parse(text)
    }

    private func executeBrowserAgentCommand(
        _ command: BrowserAgentCommand,
        inspection: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async throws -> BrowserAgentExecutionResult {
        let resolution = BrowserSemanticResolver.resolve(command, inspection: inspection)
        switch command.action {
        case .inspectPage:
            let inspection = try await controller.inspectCurrentPageForAgent()
            let controls = inspection.interactiveElements
                .prefix(5)
                .map { "\($0.label.isEmpty ? $0.text : $0.label) [\($0.selector)]" }
                .joined(separator: ", ")
            let summary = """
            Inspected \(inspection.title) at \(inspection.url). Stage: \(inspection.pageStage). Semantic targets: \(inspection.semanticTargets.count). Forms: \(inspection.forms.count), control groups: \(inspection.controlGroups.count), autocomplete surfaces: \(inspection.autocompleteSurfaces.count), date pickers: \(inspection.datePickers.count), result lists: \(inspection.resultLists.count), cards: \(inspection.cards.count), dialogs: \(inspection.dialogs.count), transactional boundaries: \(inspection.transactionalBoundaries.count). Top controls: \(controls).
            """
            return BrowserAgentExecutionResult(summary: summary, inspection: inspection)
        case .openURL:
            guard let url = command.url else {
                throw ChromiumBrowserActionError(message: "open_url requires a url.")
            }
            let state = try await controller.openURLForAgent(url)
            return BrowserAgentExecutionResult(summary: "Opened \(state.urlString). Current title: \(state.title).", inspection: nil)
        case .clickSelector:
            if let selector = resolution.selector {
                _ = try await controller.clickSelectorForAgent(
                    selector,
                    label: resolution.label,
                    transactionalKind: resolution.transactionalKind
                )
                let state = await MainActor.run { controller.browserSnapshot() }
                let targetText = resolution.label ?? selector
                return BrowserAgentExecutionResult(summary: "Clicked semantic target \(targetText). Current page: \(state.urlString).", inspection: nil)
            }
            guard let selector = command.selector else {
                throw ChromiumBrowserActionError(message: "click_selector requires a selector or semantic label.")
            }
            _ = try await controller.clickSelectorForAgent(selector, label: command.label)
            let state = await MainActor.run { controller.browserSnapshot() }
            return BrowserAgentExecutionResult(summary: "Clicked selector \(selector). Current page: \(state.urlString).", inspection: nil)
        case .clickText:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "click_text requires text.")
            }
            if let selector = resolution.selector {
                _ = try await controller.clickSelectorForAgent(
                    selector,
                    label: resolution.label ?? text,
                    transactionalKind: resolution.transactionalKind
                )
                let state = await MainActor.run { controller.browserSnapshot() }
                return BrowserAgentExecutionResult(summary: "Clicked semantic target \(resolution.label ?? text). Current page: \(state.urlString).", inspection: nil)
            }
            _ = try await controller.clickTextForAgent(text, label: command.label)
            let state = await MainActor.run { controller.browserSnapshot() }
            return BrowserAgentExecutionResult(summary: "Clicked visible text match \(text). Current page: \(state.urlString).", inspection: nil)
        case .typeText:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "type_text requires text.")
            }
            guard let selector = resolution.selector ?? command.selector else {
                throw ChromiumBrowserActionError(message: "type_text requires a selector or semantic label.")
            }
            _ = try await controller.typeTextForAgent(text, selector: selector)
            return BrowserAgentExecutionResult(summary: "Typed \(text) into \(resolution.label ?? selector).", inspection: nil)
        case .selectOption:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "select_option requires text.")
            }
            guard let selector = resolution.selector ?? command.selector else {
                throw ChromiumBrowserActionError(message: "select_option requires a selector or semantic label.")
            }
            _ = try await controller.selectOptionForAgent(text, selector: selector)
            return BrowserAgentExecutionResult(summary: "Selected option \(text) in \(resolution.label ?? selector).", inspection: nil)
        case .chooseAutocompleteOption:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "choose_autocomplete_option requires text.")
            }
            _ = try await controller.chooseAutocompleteOptionForAgent(text, selector: resolution.selector ?? command.selector)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Chose autocomplete option \(text) for \(resolution.label ?? command.label ?? "the active field").", inspection: inspection)
        case .chooseGroupedOption:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "choose_grouped_option requires text.")
            }
            _ = try await controller.chooseGroupedOptionForAgent(
                text,
                groupLabel: resolution.label ?? command.label,
                selector: resolution.selector ?? command.selector
            )
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Chose grouped option \(text) in \(resolution.label ?? command.label ?? "the matching group").", inspection: inspection)
        case .pickDate:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "pick_date requires text.")
            }
            _ = try await controller.pickDateForAgent(text, selector: resolution.selector ?? command.selector)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Picked date \(text) for \(resolution.label ?? command.label ?? "the matching date field").", inspection: inspection)
        case .submitForm:
            _ = try await controller.submitFormForAgent(
                selector: resolution.selector ?? command.selector,
                label: resolution.label ?? command.label,
                transactionalKind: resolution.transactionalKind
            )
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Submitted \(resolution.label ?? command.label ?? "the best matching form").", inspection: inspection)
        case .pressKey:
            let key = command.key ?? command.text
            guard let key else {
                throw ChromiumBrowserActionError(message: "press_key requires a key.")
            }
            _ = try await controller.pressKeyForAgent(key)
            return BrowserAgentExecutionResult(summary: "Pressed key \(key).", inspection: nil)
        case .scroll:
            let deltaY = command.deltaY ?? 600
            _ = try await controller.scrollForAgent(deltaY: deltaY)
            let state = await MainActor.run { controller.browserSnapshot() }
            return BrowserAgentExecutionResult(summary: "Scrolled the page by \(Int(deltaY)) points on \(state.urlString).", inspection: nil)
        case .waitForText:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "wait_for_text requires text.")
            }
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForTextForAgent(text, timeout: timeout)
            return BrowserAgentExecutionResult(summary: "Observed \(probe.matchCount) visible matches for \(text) on \(probe.url).", inspection: nil)
        case .waitForSelector:
            guard let selector = command.selector else {
                throw ChromiumBrowserActionError(message: "wait_for_selector requires a selector.")
            }
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForSelectorForAgent(selector, timeout: timeout)
            return BrowserAgentExecutionResult(summary: "Observed selector \(selector) on \(probe.url).", inspection: nil)
        case .waitForNavigation:
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForNavigationForAgent(expectedURLFragment: command.url, timeout: timeout)
            return BrowserAgentExecutionResult(summary: "Observed navigation to \(probe.url).", inspection: nil)
        case .waitForResults:
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForResultsForAgent(expectedText: command.text, timeout: timeout)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Observed \(probe.resultCount) visible results on \(probe.url).", inspection: inspection)
        case .waitForDialog:
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForDialogForAgent(expectedText: command.text, timeout: timeout)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Observed dialog \(probe.label.isEmpty ? "state" : probe.label) on \(probe.url).", inspection: inspection)
        case .waitForSettle:
            let timeout = command.timeoutSeconds ?? 8
            let state = try await controller.waitForSettleForAgent(timeout: timeout)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Page settled at \(state.urlString).", inspection: inspection)
        case .captureSnapshot:
            let artifact = try await controller.captureSnapshotForAgent(label: command.label)
            return BrowserAgentExecutionResult(summary: "Captured browser snapshot at \(artifact.filePath).", inspection: nil)
        case .done:
            return BrowserAgentExecutionResult(summary: command.finalResponse ?? "Browser task completed.", inspection: nil)
        }
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

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func performCodexTurn(
        prompt: String,
        session: inout AssistantSession,
        config: CodexLaunchConfig,
        forwardAssistantLines: Bool
    ) async throws -> BrowserCodexTurnResult {
        let runtimeStream = runtime.streamEvents()
        var assistantLines: [String] = []
        var stderrLines: [String] = []
        var identifiedThreadId: String?

        let bridgeTask = Task {
            for await event in runtimeStream {
                switch event {
                case let .stdoutLine(line):
                    assistantLines.append(line)
                    if forwardAssistantLines {
                        emit(.assistantDelta(line))
                    }
                case let .stderrLine(line):
                    stderrLines.append(line)
                case let .threadIdentified(threadId):
                    identifiedThreadId = threadId
                case .started, .completed:
                    break
                case let .failed(message):
                    stderrLines.append(message)
                }
            }
        }

        let result: CodexExecutionResult
        if let threadId = session.codexThreadId {
            result = try await runtime.resumeThread(threadId: threadId, prompt: prompt, config: config)
        } else {
            result = try await runtime.startNewThread(prompt: prompt, config: config)
            if let threadId = result.threadId {
                session.codexThreadId = threadId
            }
        }

        _ = await bridgeTask.result

        if let identifiedThreadId {
            session.codexThreadId = identifiedThreadId
        }

        let assistantText = assistantLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrText = (stderrLines.isEmpty ? result.stderr : stderrLines.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserCodexTurnResult(assistantText: assistantText, stderrText: stderrText, result: result)
    }

    private func persistBrowserRunArtifacts(
        outcome: String,
        goalText: String,
        initialURL: String?,
        session: AssistantSession,
        controller: ChromiumBrowserController,
        inspectionHistory: [ChromiumInspection],
        recentHistory: [String],
        finalSummary: String,
        scenarioMetadata: BrowserScenarioMetadata? = nil
    ) async throws {
        var captureWarnings: [String] = []
        do {
            _ = try await controller.captureSnapshotForAgent(label: outcome)
        } catch {
            captureWarnings.append("Automatic final snapshot failed: \(error.localizedDescription)")
        }
        let artifacts = await MainActor.run { controller.browserDebugArtifacts() }
        let record = BrowserRunArtifactRecord(
            createdAt: Date(),
            sessionId: session.id.uuidString,
            threadId: session.codexThreadId,
            outcome: outcome,
            goalText: goalText,
            initialURL: initialURL,
            scenarioID: scenarioMetadata?.id,
            scenarioTitle: scenarioMetadata?.title,
            scenarioCategory: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: goalText, initialURL: initialURL),
            finalSummary: finalSummary,
            recentHistory: recentHistory,
            inspectionHistory: inspectionHistory,
            captureWarnings: captureWarnings,
            browserArtifacts: artifacts
        )

        let directory = paths.logsDirectory
            .appendingPathComponent("browser-agent-runs", isDirectory: true)
            .appendingPathComponent(session.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let slug = outcome
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let fileURL = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(slug).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
    }

    private func retryBrowserAgentCommandIfPossible(
        _ command: BrowserAgentCommand,
        staleInspection: ChromiumInspection?,
        refreshedInspection: ChromiumInspection,
        controller: ChromiumBrowserController
    ) async throws -> BrowserAgentExecutionResult? {
        guard let resolution = BrowserSemanticResolver.bestEffortRetarget(
            command,
            staleInspection: staleInspection,
            refreshedInspection: refreshedInspection
        ) else {
            return nil
        }

        let retargetedCommand = apply(resolution: resolution, to: command)
        let result = try await executeBrowserAgentCommand(retargetedCommand, inspection: refreshedInspection, controller: controller)
        let targetDescription = resolution.label ?? resolution.selector ?? "the refreshed semantic target"
        return BrowserAgentExecutionResult(
            summary: "Recovered by re-targeting to \(targetDescription). \(result.summary)",
            inspection: result.inspection
        )
    }

    private func apply(resolution: BrowserSemanticResolution, to command: BrowserAgentCommand) -> BrowserAgentCommand {
        var updated = command
        if let selector = resolution.selector {
            updated.selector = selector
        }
        if let label = resolution.label {
            updated.label = label
        }
        if command.action == .clickText, updated.selector != nil {
            updated.action = .clickSelector
        }
        return updated
    }

    private func browserActionSignature(_ command: BrowserAgentCommand, url: String) -> String {
        let selector = command.selector ?? "-"
        let text = command.text ?? "-"
        let targetURL = command.url ?? "-"
        let key = command.key ?? "-"
        return "\(url)|\(command.action.rawValue)|\(selector)|\(text)|\(targetURL)|\(key)"
    }

    private func browserProgressSnapshot(state: ChromiumBrowserState, inspection: ChromiumInspection?) -> BrowserProgressSnapshot {
        BrowserProgressSnapshot(
            url: state.urlString,
            title: state.title,
            pageStage: inspection?.pageStage ?? "unknown",
            formCount: inspection?.forms.count ?? 0,
            resultListCount: inspection?.resultLists.count ?? 0,
            cardCount: inspection?.cards.count ?? 0,
            dialogLabels: (inspection?.dialogs ?? []).prefix(2).map { $0.label.lowercased() },
            boundaryKinds: (inspection?.transactionalBoundaries ?? []).prefix(3).map { $0.kind.lowercased() },
            primaryActionLabels: (inspection?.primaryActions ?? []).prefix(4).map { $0.label.lowercased() },
            semanticTargetLabels: (inspection?.semanticTargets ?? []).prefix(6).map { $0.label.lowercased() },
            topControlLabels: (inspection?.interactiveElements ?? [])
                .prefix(5)
                .map { ($0.label.isEmpty ? $0.text : $0.label).lowercased() }
        )
    }

    private func isRecoverableBrowserError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("no element matched")
            || normalized.contains("no visible element matched")
            || normalized.contains("no autocomplete option matched")
            || normalized.contains("no grouped control option matched")
            || normalized.contains("no visible date matched")
            || normalized.contains("timed out waiting for selector")
            || normalized.contains("timed out waiting for dialog")
            || normalized.contains("timed out waiting for search results")
    }

    private func browserRecoverySummary(
        for command: BrowserAgentCommand,
        message: String,
        inspection: ChromiumInspection,
        progressChanged: Bool
    ) -> String {
        let dialogSummary = inspection.dialogs.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let actionSummary = inspection.primaryActions.prefix(3).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let autocompleteSummary = inspection.autocompleteSurfaces.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let groupSummary = inspection.controlGroups.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let dateSummary = inspection.datePickers.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let stageSummary = inspection.pageStage
        let prefix = progressChanged
            ? "The target reported an error, but the page state changed."
            : "The target appears stale or the action was a no-op."

        switch command.action {
        case .typeText, .chooseAutocompleteOption:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible autocomplete inputs: \(autocompleteSummary.isEmpty ? "none" : autocompleteSummary)."
        case .chooseGroupedOption:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible grouped controls: \(groupSummary.isEmpty ? "none" : groupSummary)."
        case .pickDate:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible date controls: \(dateSummary.isEmpty ? "none" : dateSummary)."
        case .submitForm, .clickSelector, .clickText:
            let dialogText = dialogSummary.isEmpty ? "none" : dialogSummary
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible dialogs: \(dialogText). Top actions now: \(actionSummary.isEmpty ? "none" : actionSummary)."
        case .waitForResults:
            return "\(prefix) \(message) Page stage: \(stageSummary). Result lists: \(inspection.resultLists.count), cards: \(inspection.cards.count), top actions: \(actionSummary.isEmpty ? "none" : actionSummary)."
        case .waitForDialog:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible dialogs: \(dialogSummary.isEmpty ? "none" : dialogSummary)."
        default:
            return "\(prefix) \(message) Page stage: \(stageSummary). Inspection was refreshed with \(inspection.interactiveElements.count) visible interactive controls."
        }
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

    private func persistAssistantMessage(_ text: String, session: AssistantSession, shouldStore: Bool) throws {
        guard shouldStore else { return }
        let assistantMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            text: text,
            source: .codexStdout,
            createdAt: Date()
        )
        try sessionStore.appendMessage(assistantMessage)
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

private struct BrowserCodexTurnResult {
    let assistantText: String
    let stderrText: String
    let result: CodexExecutionResult
}

private struct BrowserRunArtifactRecord: Codable {
    let createdAt: Date
    let sessionId: String
    let threadId: String?
    let outcome: String
    let goalText: String
    let initialURL: String?
    let scenarioID: String?
    let scenarioTitle: String?
    let scenarioCategory: String
    let finalSummary: String
    let recentHistory: [String]
    let inspectionHistory: [ChromiumInspection]
    let captureWarnings: [String]
    let browserArtifacts: ChromiumBrowserDebugArtifacts
}

private struct BrowserProgressSnapshot: Equatable {
    let url: String
    let title: String
    let pageStage: String
    let formCount: Int
    let resultListCount: Int
    let cardCount: Int
    let dialogLabels: [String]
    let boundaryKinds: [String]
    let primaryActionLabels: [String]
    let semanticTargetLabels: [String]
    let topControlLabels: [String]
}
