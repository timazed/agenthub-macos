import Foundation
import IMsgCore

@MainActor
final class IMessageMonitorService {
    private let configStore: IMessageIntegrationConfigStore
    private let router: IMessageCommandRouter
    private let activityLogStore: ActivityLogStore
    private let fileManager: FileManager
    private var watchTask: Task<Void, Never>?

    init(
        configStore: IMessageIntegrationConfigStore,
        router: IMessageCommandRouter,
        activityLogStore: ActivityLogStore,
        fileManager: FileManager = .default
    ) {
        self.configStore = configStore
        self.router = router
        self.activityLogStore = activityLogStore
        self.fileManager = fileManager
    }

    func refresh() {
        do {
            let config = try configStore.loadOrCreateDefault()
            if config.isEnabled {
                startWatchingIfNeeded()
            } else {
                stopWatching()
            }
        } catch {
            appendActivity("Failed to refresh iMessage monitor: \(error.localizedDescription)")
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func startWatchingIfNeeded() {
        guard watchTask == nil else { return }

        watchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let dbPath = messagesDatabasePath()
                guard fileManager.fileExists(atPath: dbPath) else {
                    appendActivity("Messages database not found at \(dbPath)")
                    watchTask = nil
                    return
                }

                let store = try MessageStore(path: dbPath)
                let watcher = MessageWatcher(store: store)
                let configuration = MessageWatcherConfiguration(includeReactions: false)
                appendActivity("Started iMessage watcher")

                for try await message in watcher.stream(configuration: configuration) {
                    if Task.isCancelled {
                        break
                    }
                    if message.isFromMe {
                        continue
                    }

                    let incoming = buildIncomingMessage(from: message, store: store)
                    await router.handleIncomingMessage(incoming)
                }
            } catch is CancellationError {
                return
            } catch {
                appendActivity("iMessage watcher stopped: \(error.localizedDescription)")
            }

            watchTask = nil
        }
    }

    private func buildIncomingMessage(from message: IMsgCore.Message, store: MessageStore) -> IMessageIncomingMessage {
        let chatInfo = try? store.chatInfo(chatID: message.chatID)
        let sender = message.sender.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = message.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        return IMessageIncomingMessage(
            rowID: message.rowID,
            chatID: message.chatID,
            chatGUID: chatInfo?.guid.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            chatLookup: preferredChatLookup(chatInfo: chatInfo, fallbackSender: sender),
            sender: sender,
            text: text,
            date: message.date
        )
    }

    private func preferredChatLookup(chatInfo: ChatInfo?, fallbackSender: String) -> String {
        if let chatInfo {
            let preferredName = chatInfo.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferredName.isEmpty {
                return preferredName
            }
            let identifier = chatInfo.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty {
                return identifier
            }
            let guid = chatInfo.guid.trimmingCharacters(in: .whitespacesAndNewlines)
            if !guid.isEmpty {
                return guid
            }
        }

        return fallbackSender.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func messagesDatabasePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path
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
}
