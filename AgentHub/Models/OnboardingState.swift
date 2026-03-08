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
    var hasCompletedOnboarding: Bool
    var selectedPersonaId: String?
    var personalitySource: PersonalitySource?
    var updatedAt: Date

    static func `default`() -> OnboardingState {
        OnboardingState(
            hasCompletedOnboarding: false,
            selectedPersonaId: nil,
            personalitySource: nil,
            updatedAt: Date()
        )
    }
}
