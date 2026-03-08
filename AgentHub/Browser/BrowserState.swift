import Foundation

struct ChromiumBrowserState: Equatable {
    var title = "Chromium Prototype"
    var urlString = "about:blank"
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var runtimeReady = false
    var lastErrorMessage: String?
}

struct ChromiumInteractiveElement: Decodable, Equatable, Identifiable {
    let id: String
    let role: String
    let label: String
    let text: String
}

struct ChromiumInspection: Decodable, Equatable {
    let title: String
    let url: String
    let formCount: Int
    let hasSearchField: Bool
    let interactiveElements: [ChromiumInteractiveElement]
}

struct ChromiumRetryProbe: Decodable, Equatable {
    let url: String
    let title: String
    let readyState: String
    let visibleResultCount: Int
    let hasDialog: Bool

    var indicatesPageResponse: Bool {
        visibleResultCount > 0 || hasDialog
    }
}

enum ChromiumActionStatus: String, Equatable {
    case running
    case succeeded
    case failed
    case skipped
}

enum ChromiumApprovalStatus: Equatable {
    case idle
    case pending(ChromiumPendingApproval)
}

enum ChromiumFlowStatus: Equatable {
    case idle
    case running(String)
    case succeeded(String)
    case failed(String)
}

struct ChromiumRestaurantSearchRequest: Equatable {
    var siteURL: String
    var query: String
    var venueName: String
    var locationHint: String?

    static let opentableDefault = ChromiumRestaurantSearchRequest(
        siteURL: "https://www.opentable.com",
        query: "Sake House By Hikari Culver City",
        venueName: "Sake House By Hikari",
        locationHint: "Culver City"
    )
}

struct ChromiumRestaurantFlowResult: Equatable {
    let venueName: String
    let locationHint: String?
    let finalURL: String
    let finalTitle: String
}

struct ChromiumActionTraceEntry: Identifiable, Equatable {
    let id = UUID()
    let createdAt = Date()
    let name: String
    let detail: String
    let status: ChromiumActionStatus
    let attempt: Int
    let url: String
}

struct ChromiumSnapshotArtifact: Identifiable, Equatable {
    let id = UUID()
    let createdAt: Date
    let label: String
    let filePath: String
    let url: String
    let title: String
}

struct ChromiumPendingApproval: Identifiable, Equatable {
    let id = UUID()
    let actionName: String
    let detail: String
    let rationale: String
    let createdAt: Date
}

struct ChromiumLogEntry: Identifiable, Equatable {
    let id = UUID()
    let createdAt = Date()
    let message: String
}
