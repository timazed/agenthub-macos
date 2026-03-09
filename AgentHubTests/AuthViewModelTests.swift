import Foundation
import Testing
@testable import AgentHub

@MainActor
struct AuthViewModelTests {
    @Test
    func startupRefreshMarksAuthenticatedState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: makeOnboardingManager(paths: paths),
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        #expect(!viewModel.hasResolvedStartupCheck)
        await viewModel.performStartupCheckIfNeeded()

        #expect(viewModel.isAuthenticated)
        #expect(viewModel.hasResolvedStartupCheck)
        #expect(viewModel.authState.accountLabel == "user@example.com")
    }

    @Test
    func refreshStatusSurfacesUnauthenticatedState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .unauthenticated,
                    accountLabel: nil,
                    lastValidatedAt: nil,
                    failureReason: "Not logged in",
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: makeOnboardingManager(paths: paths),
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()

        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.hasResolvedStartupCheck)
        #expect(viewModel.authState.status == .unauthenticated)
        #expect(viewModel.statusTitle == "Get started with Codex")
    }

    @Test
    func beginLoginWithoutChallengeShowsBrowserWaitingState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                ),
                challenge: nil,
                loginDelayNanoseconds: 50_000_000
            ),
            initialState: .default(),
            onboardingManager: makeOnboardingManager(paths: paths),
            initialOnboardingState: .default(),
            openURL: { _ in
                Issue.record("Browser login without a challenge should not request an app-managed URL open.")
                return true
            }
        )

        let task = Task {
            await viewModel.beginLogin()
        }

        await Task.yield()

        #expect(viewModel.isAwaitingBrowserCompletion)
        #expect(viewModel.showsBrowserWaitingCard)
        #expect(viewModel.statusMessage.contains("Finish signing in in your browser"))

        await task.value

        #expect(viewModel.authState.status == .authenticated)
        #expect(viewModel.hasResolvedStartupCheck)
        #expect(!viewModel.isAwaitingBrowserCompletion)
    }

    @Test
    func cancelLoginDoesNotSurfaceError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let initialState = AuthState.default()
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                ),
                challenge: nil,
                loginDelayNanoseconds: 200_000_000,
                shouldThrowCancelledOnWait: true
            ),
            initialState: initialState,
            onboardingManager: makeOnboardingManager(paths: paths),
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        let task = Task {
            await viewModel.beginLogin()
        }

        await Task.yield()
        #expect(viewModel.isAwaitingBrowserCompletion)

        viewModel.cancelLogin()
        await task.value

        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isAwaitingBrowserCompletion)
        #expect(!viewModel.isStartingLogin)
        #expect(viewModel.authState == initialState)
    }

    @Test
    func authenticatedUserWithIncompleteOnboardingStartsAtPersonaStep() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let onboardingManager = makeOnboardingManager(paths: paths)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: onboardingManager,
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()

        #expect(viewModel.currentStep == .persona)
        #expect(!viewModel.hasCompletedOnboarding)
        #expect(viewModel.statusTitle == "Set up your assistant")
    }

    @Test
    func authStepExposesPresentationMetadata() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .unauthenticated,
                    accountLabel: nil,
                    lastValidatedAt: nil,
                    failureReason: "Not logged in",
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: makeOnboardingManager(paths: paths),
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        let presentation = viewModel.onboardingPresentation

        #expect(viewModel.currentStep == .codexAuth)
        #expect(presentation?.currentStepNumber == 1)
        #expect(presentation?.totalSteps == 3)
        #expect(presentation?.title == "Connect Codex to unlock AgentHub")
    }

    @Test
    func personaAndNameStepsExposePresentationMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let onboardingManager = makeOnboardingManager(paths: paths)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: onboardingManager,
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()

        let personaPresentation = viewModel.onboardingPresentation
        #expect(viewModel.currentStep == .persona)
        #expect(personaPresentation?.currentStepNumber == 2)
        #expect(personaPresentation?.totalSteps == 3)
        #expect(personaPresentation?.title == "Shape the assistant you want to work with")

        viewModel.savePersonality("Be direct, skeptical, and concise.")

        let namePresentation = viewModel.onboardingPresentation
        #expect(viewModel.currentStep == .name)
        #expect(namePresentation?.currentStepNumber == 3)
        #expect(namePresentation?.totalSteps == 3)
        #expect(namePresentation?.title == "Name the assistant before you enter home")
    }

    @Test
    func savePersonalityCompletesOnboardingAndPersistsDefaultPersona() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let onboardingManager = makeOnboardingManager(paths: paths)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: onboardingManager,
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()
        viewModel.savePersonality("Be direct, skeptical, and concise.")

        #expect(!viewModel.hasCompletedOnboarding)
        #expect(viewModel.currentStep == .name)
        #expect(!viewModel.onboardingState.hasCompletedOnboarding)
        #expect(viewModel.onboardingState.hasCompletedNameStep == false)
        #expect(viewModel.onboardingState.selectedPersonaId == "default")
        #expect(viewModel.onboardingState.personalitySource == .custom)

        let instructions = try PersonaManager(paths: paths).loadInstructions(personaId: "default")
        #expect(instructions == "Be direct, skeptical, and concise.\n")
    }

    @Test
    func saveAgentNameCompletesOnboardingAndPersistsDefaultPersonaName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let onboardingManager = makeOnboardingManager(paths: paths)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: onboardingManager,
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()
        viewModel.savePersonality("Be direct, skeptical, and concise.")
        viewModel.saveAgentName("Operator")

        #expect(viewModel.hasCompletedOnboarding)
        #expect(viewModel.currentStep == nil)
        #expect(viewModel.onboardingState.hasCompletedOnboarding)
        #expect(viewModel.onboardingState.hasCompletedNameStep == true)
        #expect(viewModel.onboardingState.selectedPersonaId == "default")
        #expect(viewModel.onboardingState.personalitySource == .custom)

        let persona = try PersonaManager(paths: paths).defaultPersona()
        #expect(persona.name == "Operator")
    }

    @Test
    func blankPersonalityFallsBackToDefaultInstructions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let onboardingManager = makeOnboardingManager(paths: paths)
        let viewModel = AuthViewModel(
            authManager: makeAuthManager(
                paths: paths,
                refreshedState: AuthState(
                    status: .authenticated,
                    accountLabel: "user@example.com",
                    lastValidatedAt: Date(),
                    failureReason: nil,
                    updatedAt: Date()
                )
            ),
            initialState: .default(),
            onboardingManager: onboardingManager,
            initialOnboardingState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()
        viewModel.savePersonality("   \n")

        let expected = PersonaManager(paths: paths).defaultPersonalityText()
        let instructions = try PersonaManager(paths: paths).loadInstructions(personaId: "default")
        #expect(instructions.trimmingCharacters(in: .whitespacesAndNewlines) == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private func makeOnboardingManager(paths: AppPaths) -> OnboardingManager {
    OnboardingManager(store: OnboardingStore(paths: paths), personaManager: PersonaManager(paths: paths))
}

private func makeAuthManager(
    paths: AppPaths,
    refreshedState: AuthState,
    challenge: AuthLoginChallenge? = AuthLoginChallenge(
        verificationURL: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH",
        expiresInMinutes: 15
    ),
    loginDelayNanoseconds: UInt64 = 0,
    shouldThrowCancelledOnWait: Bool = false
) -> AuthManager {
    AuthManager(
        store: AuthStore(paths: paths),
        providerClient: AuthViewModelStubProviderClient(
            refreshedState: refreshedState,
            challenge: challenge,
            loginDelayNanoseconds: loginDelayNanoseconds,
            shouldThrowCancelledOnWait: shouldThrowCancelledOnWait
        )
    )
}

private final class LoginCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func snapshot() -> Bool {
        lock.lock()
        let value = isCancelled
        lock.unlock()
        return value
    }
}

private struct AuthViewModelStubProviderClient: AuthProviderClient {
    var refreshedState: AuthState
    var challenge: AuthLoginChallenge?
    var loginDelayNanoseconds: UInt64 = 0
    var shouldThrowCancelledOnWait = false
    private let cancellationState = LoginCancellationState()

    func refreshStatus() throws -> AuthState {
        refreshedState
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        challenge
    }

    func waitForLoginCompletion() async throws -> AuthState {
        if loginDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: loginDelayNanoseconds)
        }
        if shouldThrowCancelledOnWait, cancellationState.snapshot() {
            throw CodexLoginCoordinatorError.cancelled
        }
        return refreshedState
    }

    func cancelLogin() {
        cancellationState.cancel()
    }
}
