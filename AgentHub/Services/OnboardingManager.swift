import Foundation

final class OnboardingManager {
    struct Progress: Equatable {
        let current: Int
        let total: Int
    }

    let onboardingSteps: [OnboardingStep]

    private let store: OnboardingStore
    private let personaManager: PersonaManager

    init(
        store: OnboardingStore,
        personaManager: PersonaManager,
        onboardingSteps: [OnboardingStep] = [.codexAuth, .persona, .name]
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

    func defaultAgentName() -> String {
        personaManager.defaultAgentName()
    }

    func progress(for step: OnboardingStep?) -> Progress? {
        guard let step, let index = onboardingSteps.firstIndex(of: step) else {
            return nil
        }
        return Progress(current: index + 1, total: onboardingSteps.count)
    }

    func completePersonaStep(personality: String, source: PersonalitySource) throws -> OnboardingState {
        _ = try personaManager.upsertDefaultPersona(
            name: personaManager.defaultAgentName(),
            instructions: personality
        )

        let state = OnboardingState(
            hasCompletedOnboarding: false,
            hasCompletedNameStep: false,
            selectedPersonaId: "default",
            personalitySource: source,
            updatedAt: Date()
        )
        try store.save(state)
        return state
    }

    func completeNameStep(name: String, onboardingState: OnboardingState) throws -> OnboardingState {
        try personaManager.updateDefaultPersonaName(name)

        let state = OnboardingState(
            hasCompletedOnboarding: true,
            hasCompletedNameStep: true,
            selectedPersonaId: onboardingState.selectedPersonaId ?? "default",
            personalitySource: onboardingState.personalitySource,
            updatedAt: Date()
        )
        try store.save(state)
        return state
    }

    func currentStep(authState: AuthState, onboardingState: OnboardingState) -> OnboardingStep? {
        let hasCompletedNameStep = onboardingState.hasCompletedNameStep ?? onboardingState.hasCompletedOnboarding

        for step in onboardingSteps {
            switch step {
            case .codexAuth:
                if !authState.isAuthenticated {
                    return step
                }
            case .persona:
                if authState.isAuthenticated && onboardingState.personalitySource == nil {
                    return step
                }
            case .name:
                if authState.isAuthenticated
                    && onboardingState.personalitySource != nil
                    && !hasCompletedNameStep {
                    return step
                }
            }
        }

        return nil
    }
}
