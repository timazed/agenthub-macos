import Foundation

struct ChromiumBrowserState: Codable, Equatable {
    var title = "Chromium Prototype"
    var urlString = "about:blank"
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var runtimeReady = false
    var lastErrorMessage: String?
}

struct ChromiumInteractiveElement: Codable, Equatable, Identifiable {
    let id: String
    let role: String
    let label: String
    let text: String
    let selector: String
    let value: String?
    let href: String?
    let purpose: String?
    let groupLabel: String?
    let isRequired: Bool
    let isSelected: Bool
    let validationMessage: String?
    let priority: Int
}

struct ChromiumSemanticFormField: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let controlType: String
    let value: String?
    let options: [String]
    let autocomplete: String?
    let inputMode: String?
    let fieldPurpose: String?
    let isRequired: Bool
    let isSelected: Bool
    let validationMessage: String?
}

struct ChromiumSemanticForm: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let submitLabel: String?
    let fields: [ChromiumSemanticFormField]
}

struct ChromiumSemanticCard: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let selector: String
    let actionSelector: String?
    let badges: [String]
}

struct ChromiumSemanticResultList: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let itemCount: Int
    let itemTitles: [String]
}

struct ChromiumSemanticDialog: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let primaryActionLabel: String?
    let primaryActionSelector: String?
    let dismissSelector: String?
}

struct ChromiumSemanticAction: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let role: String
    let priority: Int
}

struct ChromiumSemanticTarget: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let selector: String
    let purpose: String?
    let groupLabel: String?
    let transactionalKind: String?
    let priority: Int
}

struct ChromiumSemanticOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let isSelected: Bool
}

struct ChromiumSemanticControlGroup: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let kind: String
    let options: [ChromiumSemanticOption]
}

struct ChromiumAutocompleteSurface: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let inputSelector: String
    let optionSelector: String?
    let options: [String]
}

struct ChromiumDatePickerSemanticState: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let selectedValue: String?
    let visibleDays: [String]
    let navigationActions: [String]
}

struct ChromiumSemanticNotice: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let selector: String
}

struct ChromiumStepIndicator: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let isCurrent: Bool
}

struct ChromiumTransactionalBoundary: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let selector: String
    let confidence: Int
}

struct ChromiumBookingSlot: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let selector: String
    let score: Int
}

struct ChromiumBookingSemanticState: Codable, Equatable {
    let partySizeOptions: [String]
    let dateOptions: [String]
    let timeOptions: [String]
    let availableSlots: [ChromiumBookingSlot]
    let confirmationButtons: [String]
}

struct ChromiumBookingFunnelState: Codable, Equatable {
    let stage: String
    let selectedParameterCount: Int
    let hasVenueAction: Bool
    let hasBookingWidget: Bool
    let hasSlotSelection: Bool
    let hasGuestDetailsForm: Bool
    let hasPaymentForm: Bool
    let hasReviewSummary: Bool
    let hasFinalConfirmationBoundary: Bool
    let selectedDate: Bool
    let selectedTime: Bool
    let selectedPartySize: Bool
}

struct ChromiumInspection: Codable, Equatable {
    let title: String
    let url: String
    let pageStage: String
    let formCount: Int
    let hasSearchField: Bool
    let interactiveElements: [ChromiumInteractiveElement]
    let forms: [ChromiumSemanticForm]
    let resultLists: [ChromiumSemanticResultList]
    let cards: [ChromiumSemanticCard]
    let dialogs: [ChromiumSemanticDialog]
    let controlGroups: [ChromiumSemanticControlGroup]
    let autocompleteSurfaces: [ChromiumAutocompleteSurface]
    let datePickers: [ChromiumDatePickerSemanticState]
    let notices: [ChromiumSemanticNotice]
    let stepIndicators: [ChromiumStepIndicator]
    let primaryActions: [ChromiumSemanticAction]
    let transactionalBoundaries: [ChromiumTransactionalBoundary]
    let semanticTargets: [ChromiumSemanticTarget]
    let booking: ChromiumBookingSemanticState?
    let bookingFunnel: ChromiumBookingFunnelState?
}

struct ChromiumRetryProbe: Codable, Equatable {
    let url: String
    let title: String
    let readyState: String
    let visibleResultCount: Int
    let hasDialog: Bool

    var indicatesPageResponse: Bool {
        visibleResultCount > 0 || hasDialog
    }
}

struct ChromiumSelectorProbe: Codable, Equatable {
    let url: String
    let title: String
    let selector: String
    let found: Bool
    let text: String
}

struct ChromiumResultsProbe: Codable, Equatable {
    let url: String
    let title: String
    let found: Bool
    let resultCount: Int
    let cardCount: Int
    let listCount: Int
    let textMatchCount: Int
    let firstResultTitle: String?
}

struct ChromiumDialogProbe: Codable, Equatable {
    let url: String
    let title: String
    let found: Bool
    let label: String
    let selector: String
}

enum ChromiumActionStatus: String, Codable, Equatable {
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

struct ChromiumRestaurantBookingParameters: Codable, Equatable {
    let dateText: String?
    let timeText: String?
    let partySize: Int?

    var isSpecified: Bool {
        dateText?.isEmpty == false || timeText?.isEmpty == false || partySize != nil
    }
}

struct ChromiumRestaurantBookingRequest: Equatable {
    let searchRequest: ChromiumRestaurantSearchRequest
    let parameters: ChromiumRestaurantBookingParameters
}

struct ChromiumRestaurantBookingFlowResult: Equatable {
    let venueName: String
    let finalURL: String
    let finalTitle: String
    let selectedDate: String?
    let selectedTime: String?
    let selectedPartySize: String?
    let selectedSlot: String?
    let confirmationButtons: [String]
}

struct ChromiumActionTraceEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let name: String
    let detail: String
    let status: ChromiumActionStatus
    let attempt: Int
    let url: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        name: String,
        detail: String,
        status: ChromiumActionStatus,
        attempt: Int,
        url: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.detail = detail
        self.status = status
        self.attempt = attempt
        self.url = url
    }
}

struct ChromiumSnapshotArtifact: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let label: String
    let filePath: String
    let url: String
    let title: String

    init(
        id: UUID = UUID(),
        createdAt: Date,
        label: String,
        filePath: String,
        url: String,
        title: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.label = label
        self.filePath = filePath
        self.url = url
        self.title = title
    }
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

struct ChromiumBrowserDebugArtifacts: Codable, Equatable {
    let state: ChromiumBrowserState
    let lastInspection: ChromiumInspection?
    let actionTrace: [ChromiumActionTraceEntry]
    let snapshots: [ChromiumSnapshotArtifact]
    let flowStatusSummary: String
    let approvalStatusSummary: String
}
