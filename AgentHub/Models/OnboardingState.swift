import Foundation

enum OnboardingStep: String, Codable, CaseIterable, Hashable {
    case codexAuth
    case persona
    case name
}

enum PersonalitySource: String, Codable, Hashable {
    case `default`
    case custom
    case preset
}

struct OnboardingState: Codable, Hashable {
    var completedSteps: Set<OnboardingStep>
    var selectedPersonaId: String?
    var personalitySource: PersonalitySource?
    var defaultAgentName: String? = nil
    var updatedAt: Date

    static func `default`() -> OnboardingState {
        OnboardingState(
            completedSteps: [],
            selectedPersonaId: nil,
            personalitySource: nil,
            defaultAgentName: nil,
            updatedAt: Date()
        )
    }
}
