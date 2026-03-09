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
        var state = try store.loadOrCreateDefault()
        _ = try personaManager.upsertDefaultPersona(
            name: state.defaultAgentName ?? personaManager.defaultAgentName(),
            instructions: personality
        )

        state.selectedPersonaId = "default"
        state.personalitySource = source
        state.completedSteps.insert(.persona)
        state.updatedAt = Date()
        try store.save(state)
        return state
    }

    func completeNameStep(name: String) throws -> OnboardingState {
        var state = try store.loadOrCreateDefault()
        try personaManager.persistDefaultAgentName(name)

        state.defaultAgentName = personaManager.defaultAgentName()
        state.completedSteps.insert(.name)
        state.updatedAt = Date()
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
                if authState.isAuthenticated && !onboardingState.completedSteps.contains(.persona) {
                    return step
                }
            case .name:
                if authState.isAuthenticated
                    && onboardingState.completedSteps.contains(.persona)
                    && !onboardingState.completedSteps.contains(.name) {
                    return step
                }
            }
        }

        return nil
    }
}
