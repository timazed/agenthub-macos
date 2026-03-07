import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText = ""
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var pendingProposal: TaskProposal?
    @Published var pendingBrowserConfirmation: BrowserConfirmationRecord?
    @Published private(set) var activeModel = "gpt-5.4"
    @Published private(set) var activeReasoning = "Medium"

    private let chatSessionService: ChatSessionService
    private let taskOrchestrator: TaskOrchestrator
    private let runtimeConfigStore: AppRuntimeConfigStore

    private var streamTask: Task<Void, Never>?
    private var streamingMessageID: UUID?
    private var cancellables: Set<AnyCancellable> = []

    var onTasksChanged: (() -> Void)?
    var onActivityChanged: (() -> Void)?
    var onBrowserRequested: (() -> Void)?

    var runtimeDescriptor: String {
        "\(activeModel) · \(activeReasoning) reasoning"
    }

    init(
        chatSessionService: ChatSessionService,
        taskOrchestrator: TaskOrchestrator,
        runtimeConfigStore: AppRuntimeConfigStore
    ) {
        self.chatSessionService = chatSessionService
        self.taskOrchestrator = taskOrchestrator
        self.runtimeConfigStore = runtimeConfigStore
        loadRuntimeConfig()
        bindBrowserConfirmation()
    }

    func load() {
        loadRuntimeConfig()
        do {
            messages = try chatSessionService.loadMessages()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func confirmPendingProposal() {
        guard let proposal = pendingProposal else { return }
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

    func approvePendingBrowserConfirmation() {
        resolvePendingBrowserConfirmation(.approved)
    }

    func rejectPendingBrowserConfirmation() {
        resolvePendingBrowserConfirmation(.rejected)
    }

    func takeOverPendingBrowserConfirmation() {
        resolvePendingBrowserConfirmation(.takeOver)
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
        case .browserRequested:
            onBrowserRequested?()
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

    private func debugLog(_ message: String) {
        let line = "[AgentHub][ChatViewModel] \(message)"
        print(line)
    }

    private func bindBrowserConfirmation() {
        chatSessionService.pendingBrowserConfirmationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] confirmation in
                self?.pendingBrowserConfirmation = confirmation
            }
            .store(in: &cancellables)
    }

    private func resolvePendingBrowserConfirmation(_ resolution: BrowserConfirmationResolution) {
        guard let confirmation = pendingBrowserConfirmation else { return }

        Task {
            do {
                _ = try await chatSessionService.sendBrowserCommand(
                    .resolveConfirmation(sessionID: confirmation.sessionId, resolution: resolution)
                )
                load()
                onActivityChanged?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
