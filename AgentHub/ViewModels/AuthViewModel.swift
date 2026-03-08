import AppKit
import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var authState: AuthState
    @Published private(set) var onboardingState: OnboardingState
    @Published private(set) var currentChallenge: AuthLoginChallenge?
    @Published private(set) var isCheckingStatus = false
    @Published private(set) var isStartingLogin = false
    @Published private(set) var isAwaitingBrowserCompletion = false
    @Published private(set) var hasResolvedStartupCheck = false
    @Published var errorMessage: String?

    private let authManager: AuthManager
    private let onboardingManager: OnboardingManager
    private let openURL: (URL) -> Bool
    private var hasPerformedStartupCheck = false

    init(
        authManager: AuthManager,
        initialState: AuthState,
        onboardingManager: OnboardingManager,
        initialOnboardingState: OnboardingState,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.authManager = authManager
        self.authState = initialState
        self.onboardingManager = onboardingManager
        self.onboardingState = initialOnboardingState
        self.openURL = openURL
    }

    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    var currentStep: OnboardingStep? {
        onboardingManager.currentStep(authState: authState, onboardingState: onboardingState)
    }

    var hasCompletedOnboarding: Bool {
        currentStep == nil
    }

    var isBusy: Bool {
        isCheckingStatus || isStartingLogin || isAwaitingBrowserCompletion
    }

    var statusTitle: String {
        if isCheckingStatus {
            return "Checking Codex login"
        }
        if isStartingLogin || isAwaitingBrowserCompletion || currentChallenge != nil {
            return "Get started with Codex"
        }
        if currentStep == .persona {
            return "Set up your assistant"
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
        if currentStep == .persona {
            return "One more step: confirm the default assistant personality before entering AgentHub."
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

    var defaultPersonalityText: String {
        onboardingManager.defaultPersonalityText()
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
            onboardingState = try onboardingManager.loadState()
            hasResolvedStartupCheck = true
        } catch {
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = (try? authManager.loadCachedState()) ?? .default()
            onboardingState = (try? onboardingManager.loadState()) ?? .default()
            hasResolvedStartupCheck = true
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
            onboardingState = try onboardingManager.loadState()
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
            hasResolvedStartupCheck = true
        } catch AuthManagerError.cancelled {
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
            isStartingLogin = false
        } catch {
            currentChallenge = nil
            isAwaitingBrowserCompletion = false
            isStartingLogin = false
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = (try? authManager.loadCachedState()) ?? .default()
            onboardingState = (try? onboardingManager.loadState()) ?? .default()
        }
    }

    func cancelLogin() {
        authManager.cancelLogin()
        currentChallenge = nil
        isStartingLogin = false
        isAwaitingBrowserCompletion = false
    }

    func useDefaultPersonality() {
        savePersonality(defaultPersonalityText, source: .default)
    }

    func savePersonality(_ personality: String) {
        savePersonality(personality, source: .custom)
    }

    private func presentableErrorMessage(from message: String) -> String {
        return message
    }

    private func savePersonality(_ personality: String, source: PersonalitySource) {
        guard currentStep == .persona else { return }

        do {
            onboardingState = try onboardingManager.completePersonaStep(personality: personality, source: source)
            errorMessage = nil
        } catch {
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
        }
    }
}
