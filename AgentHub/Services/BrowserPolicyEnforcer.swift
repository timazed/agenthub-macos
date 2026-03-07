import Foundation

enum BrowserPolicyEnforcerError: LocalizedError, Equatable {
    case profileMismatch(expected: String, actual: String)
    case hostNotAllowed(host: String)
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case let .profileMismatch(expected, actual):
            return "Browser profile mismatch: expected \(expected), got \(actual)"
        case let .hostNotAllowed(host):
            return "Browser host is not allowed by policy: \(host)"
        case .confirmationRequired:
            return "Browser action requires explicit confirmation"
        }
    }
}

struct BrowserPolicyEnforcer {
    func validate(
        session: BrowserAutomationSession,
        profileId: String,
        action: BrowserAutomationAction,
        policy: BrowserPolicyRecord?,
        skipConfirmation: Bool = false
    ) throws {
        try validateSessionProfile(session: session, profileId: profileId)
        try validateAllowedHost(session: session, policy: policy)
        if !skipConfirmation {
            try validateConfirmationRequirement(session: session, action: action, policy: policy)
        }
    }

    func validateSessionProfile(session: BrowserAutomationSession, profileId: String) throws {
        guard session.profile.profileId == profileId else {
            throw BrowserPolicyEnforcerError.profileMismatch(expected: session.profile.profileId, actual: profileId)
        }
    }

    func requiresConfirmation(action: BrowserAutomationAction, policy: BrowserPolicyRecord?) -> Bool {
        guard let policy else { return false }
        let actionType = map(action)
        return policy.confirmationRules.contains(where: { $0.actionType == actionType })
    }

    private func validateAllowedHost(session: BrowserAutomationSession, policy: BrowserPolicyRecord?) throws {
        guard let policy, !policy.allowedHosts.isEmpty else { return }
        guard let currentURL = session.record.currentURL,
              let host = URL(string: currentURL)?.host else {
            throw BrowserPolicyEnforcerError.hostNotAllowed(host: "<unknown>")
        }
        guard policy.allowedHosts.contains(host) else {
            throw BrowserPolicyEnforcerError.hostNotAllowed(host: host)
        }
    }

    private func validateConfirmationRequirement(
        session: BrowserAutomationSession,
        action: BrowserAutomationAction,
        policy: BrowserPolicyRecord?
    ) throws {
        guard requiresConfirmation(action: action, policy: policy), session.mode != .awaitingConfirmation else { return }
        throw BrowserPolicyEnforcerError.confirmationRequired
    }

    private func map(_ action: BrowserAutomationAction) -> BrowserActionType {
        switch action {
        case .open:
            return .open
        case .goBack:
            return .goBack
        case .goForward:
            return .goForward
        case .reload:
            return .reload
        case .click:
            return .click
        case .fill:
            return .fill
        case .select:
            return .select
        case .submit:
            return .submit
        }
    }
}
