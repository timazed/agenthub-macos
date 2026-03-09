import Foundation

final class IMessageWhitelistService {
    enum MatchResult {
        case allowed
        case denied(String)
    }

    func match(message: IMessageIncomingMessage, config: IMessageIntegrationConfig) -> MatchResult {
        let allowedHandles = Set(config.allowedHandles.map(normalizeHandle(_:)).filter { !$0.isEmpty })

        guard !allowedHandles.isEmpty else {
            return .denied("no sender whitelist entries configured")
        }

        let normalizedHandle = normalizeHandle(message.sender)
        if !normalizedHandle.isEmpty, allowedHandles.contains(normalizedHandle) {
            return .allowed
        }

        return .denied("sender is not whitelisted")
    }

    func normalizeHandle(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        if trimmed.contains("@") {
            return trimmed
        }

        let digits = trimmed.filter { $0.isNumber }
        if trimmed.hasPrefix("+"), !digits.isEmpty {
            return "+\(digits)"
        }
        if !digits.isEmpty {
            return digits
        }

        return trimmed
    }
}
