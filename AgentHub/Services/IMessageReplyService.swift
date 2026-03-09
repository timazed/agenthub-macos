import Foundation
import IMsgCore

final class IMessageReplyService {
    private let sender = MessageSender()
    private let region = Locale.current.region?.identifier ?? "US"

    func sendReply(text: String, to recipient: String) async throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty, !normalizedRecipient.isEmpty else { return }

        try await MainActor.run {
            try sender.send(
                MessageSendOptions(
                    recipient: normalizedRecipient,
                    text: normalizedText,
                    service: .auto,
                    region: region
                )
            )
        }
    }
}
