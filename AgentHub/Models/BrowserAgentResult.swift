import Foundation

enum BrowserAgentResultKind: Equatable {
    case inspection
    case actionExecuted
    case confirmationRequired
    case confirmationResolved
}

struct BrowserAgentResult: Equatable {
    var kind: BrowserAgentResultKind
    var summary: String
    var snapshot: BrowserPageSnapshot?
    var confirmation: BrowserConfirmationRecord?
}
