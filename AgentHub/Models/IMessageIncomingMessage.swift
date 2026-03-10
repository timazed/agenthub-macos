import Foundation

struct IMessageIncomingMessage: Identifiable, Codable, Hashable {
    var rowID: Int64
    var chatID: Int64
    var chatGUID: String
    var chatLookup: String
    var sender: String
    var text: String
    var date: Date

    var id: Int64 { rowID }

    var replyRecipient: String {
        sender.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
