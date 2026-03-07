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

    private let authManager: AuthManaging
    private let openURL: (URL) -> Bool
    private var hasPerformedStartupCheck = false

    init(
        authManager: AuthManaging,
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

    var currentProvider: AuthProvider {
        authState.provider
    }

    var availableProviders: [AuthProvider] {
        authManager.availableProviders
    }

    var canStartLogin: Bool {
        authManager.capabilities.isAvailable && !authManager.capabilities.authMethods.isEmpty
    }

    var canUseApp: Bool {
        authState.isAuthenticated && authManager.capabilities.supportsChat
    }

    var isBusy: Bool {
        isCheckingStatus || isStartingLogin || isAwaitingBrowserCompletion
    }

    var statusTitle: String {
        if !authManager.capabilities.isAvailable {
            return "\(providerDisplayName) is unavailable"
        }
        if isCheckingStatus {
            return "Checking \(providerDisplayName) login"
        }
        switch authState.status {
        case .authenticated:
            if !authManager.capabilities.supportsChat {
                return "\(providerDisplayName) is connected"
            }
            return "\(providerDisplayName) is ready"
        case .failed:
            return "\(providerDisplayName) login check failed"
        case .unauthenticated, .unknown:
            return "Get started with \(providerDisplayName)"
        }
    }

    var statusMessage: String {
        if let message = authManager.capabilities.availabilityMessage, !authManager.capabilities.isAvailable {
            return message
        }
        if currentChallenge != nil {
            return "Open the browser sign-in page, then enter the one-time code below to finish connecting \(providerDisplayName)."
        }
        if isAwaitingBrowserCompletion {
            return "Finish signing in in your browser. AgentHub will continue as soon as \(providerDisplayName) reports that login is complete."
        }
        if isCheckingStatus {
            return "Validating whether the bundled \(providerDisplayName) CLI can run commands with your account."
        }
        switch authState.status {
        case .authenticated:
            if !authManager.capabilities.supportsChat {
                return authManager.capabilities.availabilityMessage ?? "\(providerDisplayName) auth is set up, but runtime support is not available yet."
            }
            if let accountLabel {
                return "Signed in as \(accountLabel)."
            }
            return "Your \(providerDisplayName) account is authenticated."
        case .failed:
            return authState.failureReason ?? "AgentHub could not validate \(providerDisplayName) login."
        case .unauthenticated:
            return "Sign in before using chat or background tasks."
        case .unknown:
            return "AgentHub needs a \(providerDisplayName) login before it can run commands."
        }
    }

    var accountLabel: String? {
        authState.accountLabel
    }

    var providerDisplayName: String {
        authState.provider.displayName
    }

    var primaryButtonTitle: String {
        if isBusy {
            return "Working…"
        }
        guard canStartLogin else {
            return "\(providerDisplayName) unavailable"
        }
        return "Get started with \(providerDisplayName)"
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

    func selectProvider(_ provider: AuthProvider) async {
        guard provider != authState.provider else { return }

        cancelLogin()
        errorMessage = nil
        currentChallenge = nil

        do {
            authState = try authManager.selectProvider(provider)
            hasPerformedStartupCheck = false
            await refreshStatus()
        } catch {
            errorMessage = presentableErrorMessage(from: error.localizedDescription)
            authState = AuthState(
                provider: provider,
                status: .failed,
                accountLabel: nil,
                lastValidatedAt: nil,
                failureReason: error.localizedDescription,
                updatedAt: Date()
            )
        }
    }

    func beginLogin() async {
        guard !isBusy else { return }
        guard canStartLogin else {
            errorMessage = authManager.capabilities.availabilityMessage ?? "\(providerDisplayName) login is not available."
            return
        }

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
