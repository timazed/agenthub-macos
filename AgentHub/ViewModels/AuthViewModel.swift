import AppKit
import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var authState: CodexAuthState
    @Published private(set) var currentChallenge: CodexDeviceAuthChallenge?
    @Published private(set) var isCheckingStatus = false
    @Published private(set) var isStartingLogin = false
    @Published private(set) var isAwaitingBrowserCompletion = false
    @Published var errorMessage: String?

    private let authService: CodexAuthService
    private let loginCoordinator: CodexLoginCoordinator
    private let openURL: (URL) -> Bool
    private var hasPerformedStartupCheck = false

    init(
        authService: CodexAuthService,
        loginCoordinator: CodexLoginCoordinator,
        initialState: CodexAuthState,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.authService = authService
        self.loginCoordinator = loginCoordinator
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
        if isCheckingStatus {
            return "Validating whether the bundled Codex CLI can run commands with your account."
        }
        switch authState.status {
        case .authenticated:
            if let email = authState.accountEmail {
                return "Signed in as \(email)."
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

    var primaryButtonTitle: String {
        isBusy ? "Working…" : "Get started with Codex"
    }

    var showsDeviceAuthorizationHelp: Bool {
        normalizedFailureText.contains("enable device code authorization")
    }

    var securitySettingsURL: URL? {
        URL(string: "https://chatgpt.com/")
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
            authState = try authService.refreshStatus()
        } catch {
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = (try? authService.loadCachedState()) ?? .default()
        }

        isCheckingStatus = false
    }

    func beginLogin() async {
        guard !isBusy else { return }

        isStartingLogin = true
        errorMessage = nil
        currentChallenge = nil

        do {
            let challenge = try await loginCoordinator.startLogin()
            currentChallenge = challenge
            isStartingLogin = false
            isAwaitingBrowserCompletion = true

            let opened = openURL(challenge.verificationURL)
            if !opened {
                errorMessage = "AgentHub could not open the browser automatically."
            }

            let state = try await loginCoordinator.waitForCompletion()
            authState = state
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
        } catch {
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
            isStartingLogin = false
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = (try? authService.loadCachedState()) ?? .default()
        }
    }

    func cancelLogin() {
        loginCoordinator.cancel()
        currentChallenge = nil
        isStartingLogin = false
        isAwaitingBrowserCompletion = false
    }

    private var normalizedFailureText: String {
        (errorMessage ?? authState.failureReason ?? "").lowercased()
    }

    private func presentableErrorMessage(from message: String) -> String {
        if message.lowercased().contains("enable device code authorization") {
            return "Enable device code authorization for Codex in ChatGPT Settings > Security, then try again."
        }
        return message
    }
}
