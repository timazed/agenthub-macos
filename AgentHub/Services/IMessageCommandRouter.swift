import Foundation

final class IMessageCommandRouter {
    private let configStore: IMessageIntegrationConfigStore
    private let whitelistService: IMessageWhitelistService
    private let mentionParser: IMessageMentionParser
    private let executionService: ExternalAgentExecutionService
    private let replyService: IMessageReplyService
    private let activityLogStore: ActivityLogStore
    private let sessionStore: AssistantSessionStore
    private let personaManager: PersonaManager

    init(
        configStore: IMessageIntegrationConfigStore,
        whitelistService: IMessageWhitelistService,
        mentionParser: IMessageMentionParser,
        executionService: ExternalAgentExecutionService,
        replyService: IMessageReplyService,
        activityLogStore: ActivityLogStore,
        sessionStore: AssistantSessionStore,
        personaManager: PersonaManager
    ) {
        self.configStore = configStore
        self.whitelistService = whitelistService
        self.mentionParser = mentionParser
        self.executionService = executionService
        self.replyService = replyService
        self.activityLogStore = activityLogStore
        self.sessionStore = sessionStore
        self.personaManager = personaManager
    }

    func handleIncomingMessage(_ message: IMessageIncomingMessage) async {
        do {
            let config = try configStore.loadOrCreateDefault()
            appendActivity("Incoming iMessage from \(message.sender)")

            guard config.isEnabled else {
                appendActivity("Ignored iMessage from \(message.sender): integration disabled")
                return
            }

            switch whitelistService.match(message: message, config: config) {
            case .allowed:
                break
            case let .denied(reason):
                appendActivity("Ignored iMessage from \(message.sender): \(reason)")
                return
            }

            guard let parsedCommand = try mentionParser.parse(message.text) else {
                appendActivity("Ignored iMessage from \(message.sender): no agent mention found")
                return
            }

            try appendTranscriptMessage(
                role: .user,
                text: formattedIncomingMessageText(for: message),
                source: .iMessageIncoming,
                createdAt: message.date
            )
            appendActivity("Running \(parsedCommand.persona.name) for iMessage from \(message.sender)")
            setExternalRunState(true)
            let response = try await executionService.execute(persona: parsedCommand.persona, prompt: parsedCommand.prompt)
            setExternalRunState(false)

            guard !response.isEmpty else {
                appendActivity("Skipped empty iMessage reply for \(parsedCommand.persona.name)")
                return
            }

            let replyText = "\(parsedCommand.persona.name):\n\n\(response)"
            try await replyService.sendReply(text: replyText, to: message.replyRecipient)
            try appendTranscriptMessage(
                role: .assistant,
                text: response,
                source: .iMessageOutgoing,
                createdAt: Date()
            )
            appendActivity("Sent iMessage reply from \(parsedCommand.persona.name) to \(message.sender)")
        } catch {
            setExternalRunState(false)
            appendActivity("iMessage handling failed: \(error.localizedDescription)")
        }
    }

    private func appendActivity(_ message: String) {
        try? activityLogStore.append(
            ActivityEvent(
                id: UUID(),
                taskId: nil,
                kind: .iMessageEvent,
                message: message,
                createdAt: Date()
            )
        )
    }

    private func appendTranscriptMessage(
        role: MessageRole,
        text: String,
        source: MessageSource,
        createdAt: Date
    ) throws {
        let persona = try personaManager.defaultPersona()
        let session = try sessionStore.loadOrCreateDefault(personaId: persona.id)
        try sessionStore.appendMessage(
            Message(
                id: UUID(),
                sessionId: session.id,
                role: role,
                text: text,
                source: source,
                createdAt: createdAt
            )
        )
    }

    private func formattedIncomingMessageText(for message: IMessageIncomingMessage) -> String {
        let sender = message.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let chat = message.chatLookup.trimmingCharacters(in: .whitespacesAndNewlines)

        if !chat.isEmpty, chat.caseInsensitiveCompare(sender) != .orderedSame {
            return "iMessage from \(sender) in \(chat)\n\n\(message.text)"
        }
        return "iMessage from \(sender)\n\n\(message.text)"
    }

    private func setExternalRunState(_ isActive: Bool) {
        NotificationCenter.default.post(
            name: .assistantExternalRunStateDidChange,
            object: nil,
            userInfo: ["isActive": isActive]
        )
    }
}
