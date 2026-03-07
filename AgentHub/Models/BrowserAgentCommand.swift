import Foundation

enum BrowserAgentCommand: Equatable {
    case inspect(sessionID: UUID)
    case execute(sessionID: UUID, profileId: String, action: BrowserAutomationAction)
    case resolveConfirmation(sessionID: UUID, resolution: BrowserConfirmationResolution)
}
