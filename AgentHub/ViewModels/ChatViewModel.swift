import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText = ""
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var pendingProposal: TaskProposal?
    @Published private(set) var activeModel = "gpt-5.4"
    @Published private(set) var activeReasoning = "Medium"
    @Published private(set) var agentName = "Agent"
    @Published private(set) var agentProfilePictureURL: String?
    @Published private(set) var isExternalRunActive = false

    private let chatSessionService: ChatSessionService
    private let taskOrchestrator: TaskOrchestrator
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let personaManager: PersonaManager
    private var transcriptObserver: NSObjectProtocol?
    private var externalRunObserver: NSObjectProtocol?

    private var streamTask: Task<Void, Never>?
    private var streamingMessageID: UUID?

    var onTasksChanged: (() -> Void)?
    var onActivityChanged: (() -> Void)?

    var headerDescriptor: String {
        "\(activeReasoning) reasoning"
    }

    var isThinking: Bool {
        isBusy || isExternalRunActive
    }

    var supportedModels: [SupportedModel] {
        if AppRuntimeConfig.supportedModels.contains(where: { $0.id.caseInsensitiveCompare(activeModel) == .orderedSame }) {
            return AppRuntimeConfig.supportedModels
        }
        return AppRuntimeConfig.supportedModels + [
            SupportedModel(id: activeModel, displayName: SupportedModel.displayName(for: activeModel))
        ]
    }

    init(
        chatSessionService: ChatSessionService,
        taskOrchestrator: TaskOrchestrator,
        runtimeConfigStore: AppRuntimeConfigStore,
        personaManager: PersonaManager
    ) {
        self.chatSessionService = chatSessionService
        self.taskOrchestrator = taskOrchestrator
        self.runtimeConfigStore = runtimeConfigStore
        self.personaManager = personaManager
        transcriptObserver = NotificationCenter.default.addObserver(
            forName: .assistantTranscriptDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadMessages()
            }
        }
        externalRunObserver = NotificationCenter.default.addObserver(
            forName: .assistantExternalRunStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let isActive = notification.userInfo?["isActive"] as? Bool ?? false
            Task { @MainActor [weak self] in
                self?.isExternalRunActive = isActive
            }
        }
        loadRuntimeConfig()
        loadPersonaProfile()
    }

    func load() {
        loadRuntimeConfig()
        loadPersonaProfile()
        reloadMessages()
    }

    func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        let localUser = Message(
            id: UUID(),
            sessionId: UUID(),
            role: .user,
            text: text,
            source: .userInput,
            createdAt: Date()
        )
        messages.append(localUser)

        Task {
            await send(text: text)
        }
    }

    func cancel() {
        do {
            try chatSessionService.cancelCurrentRun()
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    func confirmPendingProposal(_ proposal: TaskProposal? = nil) {
        guard let proposal = proposal ?? pendingProposal else { return }
        pendingProposal = nil

        Task {
            do {
                _ = try await taskOrchestrator.createTask(from: proposal)
                onTasksChanged?()
                onActivityChanged?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissPendingProposal() {
        pendingProposal = nil
    }

    func setActiveModel(_ model: String) {
        guard model != activeModel else { return }

        do {
            var config = try runtimeConfigStore.loadOrCreateDefault()
            config.model = model
            config.updatedAt = Date()
            try runtimeConfigStore.save(config)
            activeModel = model
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setActiveReasoning(_ reasoning: ReasoningEffort) {
        guard reasoning.displayName != activeReasoning else { return }

        do {
            var config = try runtimeConfigStore.loadOrCreateDefault()
            config.reasoningEffort = reasoning
            config.updatedAt = Date()
            try runtimeConfigStore.save(config)
            activeReasoning = reasoning.displayName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(text: String) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        streamingMessageID = nil

        let stream = chatSessionService.streamEvents()
        streamTask?.cancel()
        streamTask = Task {
            for await event in stream {
                await handle(event)
            }
        }

        do {
            try await chatSessionService.sendUserMessage(text)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }

        isBusy = false
        onActivityChanged?()
    }

    private func handle(_ event: ChatSessionEvent) async {
        switch event {
        case let .assistantDelta(line):
            appendStreamingAssistantLine(line)
        case let .stderr(line):
            debugLog("stderr \(line)")
        case let .proposal(proposal):
            pendingProposal = proposal
        case .completed:
            break
        case let .failed(message):
            debugLog("failed \(message)")
            errorMessage = message
        }
    }

    private func appendStreamingAssistantLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let streamingMessageID,
           let index = messages.firstIndex(where: { $0.id == streamingMessageID }) {
            let existing = messages[index].text
            messages[index].text = existing.isEmpty ? trimmed : "\(existing)\n\(trimmed)"
            return
        }

        let messageID = UUID()
        streamingMessageID = messageID
        messages.append(
            Message(
                id: messageID,
                sessionId: UUID(),
                role: .assistant,
                text: trimmed,
                source: .codexStdout,
                createdAt: Date()
            )
        )
    }

    private func loadRuntimeConfig() {
        do {
            let config = try runtimeConfigStore.loadOrCreateDefault()
            activeModel = config.model
            activeReasoning = config.reasoningEffort.displayName
        } catch {
            debugLog("runtime_config_failed \(error.localizedDescription)")
        }
    }

    private func loadPersonaProfile() {
        do {
            let persona = try personaManager.defaultPersona()
            let trimmedName = persona.name.trimmingCharacters(in: .whitespacesAndNewlines)
            agentName = trimmedName.isEmpty ? "Agent" : trimmedName
            agentProfilePictureURL = persona.profilePictureURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            agentName = "Agent"
            agentProfilePictureURL = nil
            debugLog("persona_profile_failed \(error.localizedDescription)")
        }
    }

    private func debugLog(_ message: String) {
        let line = "[AgentHub][ChatViewModel] \(message)"
        print(line)
    }

    private func reloadMessages() {
        do {
            messages = try chatSessionService.loadMessages()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        if let transcriptObserver {
            NotificationCenter.default.removeObserver(transcriptObserver)
        }
        if let externalRunObserver {
            NotificationCenter.default.removeObserver(externalRunObserver)
        }
    }
}
