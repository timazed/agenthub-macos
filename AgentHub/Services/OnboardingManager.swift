import Foundation

final class OnboardingManager {
    let onboardingSteps: [OnboardingStep]

    private let store: OnboardingStore

    init(
        store: OnboardingStore,
        onboardingSteps: [OnboardingStep] = [.codexAuth, .persona]
    ) {
        self.store = store
        self.onboardingSteps = onboardingSteps
    }

    func loadState() throws -> OnboardingState {
        try store.loadOrCreateDefault()
    }

    func saveState(_ state: OnboardingState) throws {
        try store.save(state)
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
