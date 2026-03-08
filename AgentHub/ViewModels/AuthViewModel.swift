import AppKit
import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var authState: AuthState
    @Published private(set) var currentChallenge: AuthLoginChallenge?
    @Published private(set) var isCheckingStatus = false
    @Published private(set) var isStartingLogin = false
    @Published private(set) var isAwaitingBrowserCompletion = false
    @Published var errorMessage: String?

    private let authManager: AuthManager
    private let openURL: (URL) -> Bool
    private var hasPerformedStartupCheck = false

    init(
        authManager: AuthManager,
        initialState: AuthState,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.authManager = authManager
        self.authState = initialState
        self.openURL = openURL
    }

    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    var isBusy: Bool {
        isCheckingStatus || isStartingLogin || isAwaitingBrowserCompletion
    }

    var statusTitle: String {
        if isCheckingStatus {
            return "Checking Codex login"
        }
        switch authState.status {
        case .authenticated:
            return "Codex is ready"
        case .failed:
            return "Codex login check failed"
        case .unauthenticated, .unknown:
            return "Get started with Codex"
        }
    }

    var statusMessage: String {
        if currentChallenge != nil {
            return "Open the browser sign-in page, then enter the one-time code below to finish connecting Codex."
        }
        if isAwaitingBrowserCompletion {
            return "Finish signing in in your browser. AgentHub will continue as soon as Codex reports that login is complete."
        }
        if isCheckingStatus {
            return "Validating whether the bundled Codex CLI can run commands with your account."
        }
        switch authState.status {
        case .authenticated:
            if let accountLabel {
                return "Signed in as \(accountLabel)."
            }
            return "Your Codex account is authenticated."
        case .failed:
            return authState.failureReason ?? "AgentHub could not validate Codex login."
        case .unauthenticated:
            return "Sign in before using chat or background tasks."
        case .unknown:
            return "AgentHub needs a Codex login before it can run commands."
        }
    }

    var accountLabel: String? {
        authState.accountLabel
    }

    var primaryButtonTitle: String {
        isBusy ? "Working…" : "Get started with Codex"
    }

    var showsBrowserWaitingCard: Bool {
        isAwaitingBrowserCompletion && currentChallenge == nil
    }

    func performStartupCheckIfNeeded() async {
        guard !hasPerformedStartupCheck else { return }
        hasPerformedStartupCheck = true
        await refreshStatus()
    }

    func refreshStatus() async {
        isCheckingStatus = true
        errorMessage = nil

        do {
            authState = try authManager.refreshStatus()
        } catch {
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = (try? authManager.loadCachedState()) ?? .default()
        }

        isCheckingStatus = false
    }

    func beginLogin() async {
        guard !isBusy else { return }

        isStartingLogin = true
        errorMessage = nil
        currentChallenge = nil

        do {
            let challenge = try await authManager.startLogin()
            isStartingLogin = false
            isAwaitingBrowserCompletion = true

            if let challenge {
                currentChallenge = challenge
                let opened = openURL(challenge.verificationURL)
                if !opened {
                    errorMessage = "AgentHub could not open the browser automatically."
                }
            }

            let state = try await authManager.waitForLoginCompletion()
            authState = state
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
        } catch {
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
            isStartingLogin = false
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = (try? authManager.loadCachedState()) ?? .default()
        }
    }

    func cancelLogin() {
        authManager.cancelLogin()
        currentChallenge = nil
        isStartingLogin = false
        isAwaitingBrowserCompletion = false
    }

    private func presentableErrorMessage(from message: String) -> String {
        return message
    }
}
