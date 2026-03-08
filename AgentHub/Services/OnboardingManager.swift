import Foundation

final class OnboardingManager {
    let onboardingSteps: [OnboardingStep]

    private let store: OnboardingStore
    private let personaManager: PersonaManager

    init(
        store: OnboardingStore,
        personaManager: PersonaManager,
        onboardingSteps: [OnboardingStep] = [.codexAuth, .persona]
    ) {
        self.store = store
        self.personaManager = personaManager
        self.onboardingSteps = onboardingSteps
    }

    func loadState() throws -> OnboardingState {
        try store.loadOrCreateDefault()
    }

    func saveState(_ state: OnboardingState) throws {
        try store.save(state)
    }

    func defaultPersonalityText() -> String {
        personaManager.defaultPersonalityText()
    }

    func completePersonaStep(personality: String, source: PersonalitySource) throws -> OnboardingState {
        _ = try personaManager.upsertDefaultPersona(personality: personality)

        let state = OnboardingState(
            hasCompletedOnboarding: true,
            selectedPersonaId: "default",
            personalitySource: source,
            updatedAt: Date()
        )
        try store.save(state)
        return state
    }

    func currentStep(authState: AuthState, onboardingState: OnboardingState) -> OnboardingStep? {
        for step in onboardingSteps {
            switch step {
            case .codexAuth:
                if !authState.isAuthenticated {
                    return step
                }
            case .persona:
                if authState.isAuthenticated && !onboardingState.hasCompletedOnboarding {
                    return step
                }
            case .name:
                continue
            }
        }

        return nil
    }
}
