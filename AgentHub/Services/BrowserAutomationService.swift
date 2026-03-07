import Combine
import Foundation

@MainActor
final class BrowserAutomationService: ObservableObject {
    @Published private(set) var activeSession: BrowserAutomationSession?
    @Published private(set) var pendingConfirmation: BrowserConfirmationRecord?

    private let policyEnforcer: BrowserPolicyEnforcer
    private let policyRegistry: BrowserPolicyRegistry
    private let confirmationStore: BrowserConfirmationStore
    private var approvedConfirmation: BrowserConfirmationRecord?

    init() {
        self.policyEnforcer = BrowserPolicyEnforcer()
        let paths = AppPaths(root: AppPaths.defaultRoot())
        self.policyRegistry = BrowserPolicyRegistry(paths: paths)
        self.confirmationStore = BrowserConfirmationStore(paths: paths)
    }

    init(
        policyEnforcer: BrowserPolicyEnforcer,
        policyRegistry: BrowserPolicyRegistry,
        confirmationStore: BrowserConfirmationStore
    ) {
        self.policyEnforcer = policyEnforcer
        self.policyRegistry = policyRegistry
        self.confirmationStore = confirmationStore
    }

    @discardableResult
    func startSession(profile: BrowserProfile) -> BrowserAutomationSession {
        if let activeSession, activeSession.profile.profileId == profile.profileId {
            return activeSession
        }

        let session = BrowserAutomationSession(profile: profile)
        activeSession = session
        return session
    }

    func attach(webView: BrowserWebViewControlling, to sessionID: UUID) {
        guard let activeSession, activeSession.record.id == sessionID else { return }
        activeSession.attach(webView: webView)
    }

    func detach(sessionID: UUID) {
        guard let activeSession, activeSession.record.id == sessionID else { return }
        activeSession.detachWebView()
    }

    func setMode(_ mode: BrowserSessionMode, sessionID: UUID) {
        guard let activeSession, activeSession.record.id == sessionID else { return }
        activeSession.setMode(mode)
    }

    func execute(_ action: BrowserAutomationAction, sessionID: UUID, profileId: String) async throws {
        guard let activeSession, activeSession.record.id == sessionID else {
            throw BrowserAutomationSessionError.sessionUnavailable
        }

        let policy = try policyRegistry.policy(for: profileId)
        let approvedAction = matchesApprovedConfirmation(action, sessionID: sessionID, profileId: profileId)
        do {
            try policyEnforcer.validate(
                session: activeSession,
                profileId: profileId,
                action: action,
                policy: policy,
                skipConfirmation: approvedAction
            )
        } catch BrowserPolicyEnforcerError.confirmationRequired {
            let confirmation = BrowserConfirmationRecord(
                id: UUID(),
                sessionId: activeSession.record.id,
                profileId: profileId,
                actionType: map(action),
                target: describeTarget(action),
                currentURL: activeSession.record.currentURL,
                pageTitle: activeSession.record.title,
                resolution: .pending,
                createdAt: Date(),
                resolvedAt: nil
            )
            try confirmationStore.upsert(confirmation)
            pendingConfirmation = confirmation
            activeSession.setMode(.awaitingConfirmation)
            throw BrowserPolicyEnforcerError.confirmationRequired
        }

        if approvedAction {
            approvedConfirmation = nil
        }
        try await activeSession.execute(action)
    }

    func inspectPage(sessionID: UUID) async throws -> BrowserPageSnapshot {
        guard let activeSession, activeSession.record.id == sessionID else {
            throw BrowserAutomationSessionError.sessionUnavailable
        }

        return try await activeSession.inspectPage()
    }

    func resolveConfirmation(sessionID: UUID, resolution: BrowserConfirmationResolution) throws {
        guard let activeSession, activeSession.record.id == sessionID else {
            throw BrowserAutomationSessionError.sessionUnavailable
        }
        guard var confirmation = try confirmationStore.pending(for: sessionID) else { return }

        confirmation.resolution = resolution
        confirmation.resolvedAt = Date()
        try confirmationStore.upsert(confirmation)
        pendingConfirmation = confirmation.resolution == .pending ? confirmation : nil

        switch resolution {
        case .approved:
            approvedConfirmation = confirmation
            activeSession.setMode(.agentControlling)
        case .rejected, .takeOver:
            approvedConfirmation = nil
            activeSession.setMode(.manual)
        case .pending:
            activeSession.setMode(.awaitingConfirmation)
        }
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

    private func describeTarget(_ action: BrowserAutomationAction) -> String? {
        switch action {
        case let .click(targetID):
            return targetID
        case let .fill(targetID, _):
            return targetID
        case let .select(targetID, _):
            return targetID
        case let .submit(targetID):
            return targetID
        case .open, .goBack, .goForward, .reload:
            return nil
        }
    }

    private func matchesApprovedConfirmation(_ action: BrowserAutomationAction, sessionID: UUID, profileId: String) -> Bool {
        guard let approvedConfirmation else { return false }
        return approvedConfirmation.sessionId == sessionID
            && approvedConfirmation.profileId == profileId
            && approvedConfirmation.actionType == map(action)
            && approvedConfirmation.target == describeTarget(action)
    }
}
