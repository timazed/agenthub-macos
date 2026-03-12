import AppKit
import Combine
import Foundation
import Vision

struct ChromiumBrowserActionError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class ChromiumBrowserController: NSObject, ObservableObject {
    private struct RetryPolicy {
        let attempts: Int
        let delay: TimeInterval
    }

    struct VisibleTextProbe: Decodable {
        let url: String
        let title: String
        let matchCount: Int
        let firstMatch: String
    }

    private struct BrowserProgressMarker: Equatable {
        let url: String
        let title: String
        let visibleLabels: [String]
    }

    private struct ScrollCaptureRect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private struct ScrollCapturePlan: Decodable {
        let mode: String
        let offsets: [Double]
        let originalOffset: Double
        let viewportHeight: Double
        let contentHeight: Double
        let viewportRect: ScrollCaptureRect
    }

    private struct ScrollCapturePosition: Decodable {
        let mode: String
        let actualOffset: Double
        let viewportRect: ScrollCaptureRect
    }

    static func nativeVerificationAutofillReady(_ details: [String: Any]?) -> Bool {
        guard let details else { return false }
        let focused = details["focused"] as? Bool ?? false
        let hasInputContext = details["hasInputContext"] as? Bool ?? false
        let responderClass = (details["responderClass"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inputClientClass = (details["inputClientClass"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard focused, hasInputContext else {
            return false
        }
        guard !responderClass.isEmpty, !inputClientClass.isEmpty else {
            return false
        }
        return responderClass == inputClientClass
    }

    @Published private(set) var state = ChromiumBrowserState()
    @Published private(set) var lastInspection: ChromiumInspection?
    @Published private(set) var logs: [ChromiumLogEntry] = []
    @Published private(set) var actionTrace: [ChromiumActionTraceEntry] = []
    @Published private(set) var snapshots: [ChromiumSnapshotArtifact] = []
    @Published private(set) var flowStatus: ChromiumFlowStatus = .idle
    @Published private(set) var approvalStatus: ChromiumApprovalStatus = .idle
    @Published private(set) var browserViewIdentity = UUID()

    @Published var addressBarText = "https://www.opentable.com"
    @Published var quickSearchText = "Sake House By Hikari Culver City"
    @Published var textMatch = "Sake House By Hikari"
    @Published var selectorText = ""
    @Published var selectorInputText = ""
    @Published private(set) var isEditingAddressBar = false

    private(set) var browserView: AHChromiumBrowserView
    private var lastSyncedBrowserURL = "about:blank"
    private var activeRestaurantRequest = ChromiumRestaurantSearchRequest.opentableDefault
    private var lastApprovalDecision: Bool?

    override init() {
        browserView = AHChromiumBrowserView(frame: .zero)
        super.init()
        browserView.delegate = self
        syncStateFromView()
    }

    func openCurrentAddress() {
        let trimmed = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isEditingAddressBar = false
        addressBarText = trimmed
        activeRestaurantRequest.siteURL = trimmed
        appendLog("Opening \(trimmed)")
        browserView.loadURLString(trimmed)
    }

    func runRestaurantSearchFlow() {
        let trimmedAddress = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = quickSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVenueName = textMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        activeRestaurantRequest = ChromiumRestaurantSearchRequest(
            siteURL: trimmedAddress.isEmpty
                ? ChromiumRestaurantSearchRequest.opentableDefault.siteURL
                : trimmedAddress,
            query: trimmedQuery,
            venueName: trimmedVenueName,
            locationHint: inferredLocationHint(query: trimmedQuery, venueName: trimmedVenueName)
        )
        Task {
            do {
                _ = try await runRestaurantSearchFlow(request: activeRestaurantRequest)
            } catch {
                let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                flowStatus = .failed(message)
                appendLog("Restaurant flow failed: \(message)")
            }
        }
    }

    func runRestaurantSearchFlow(
        request: ChromiumRestaurantSearchRequest,
        progress: ((String) -> Void)? = nil
    ) async throws -> ChromiumRestaurantFlowResult {
        guard !request.siteURL.isEmpty, !request.query.isEmpty, !request.venueName.isEmpty else {
            let message = "Restaurant flow requires a site URL, search query, and exact result text."
            flowStatus = .failed(message)
            throw ChromiumBrowserActionError(message: message)
        }

        activeRestaurantRequest = request
        addressBarText = request.siteURL
        quickSearchText = request.query
        textMatch = request.venueName
        selectorText = ""
        selectorInputText = ""

        flowStatus = .running("Opening search page")
        actionTrace.removeAll()
        appendLog("Starting deterministic restaurant flow for \(request.venueName).")
        progress?("Opening OpenTable in the embedded Chromium browser.")

        do {
            try await openURLAndWaitUntilReady(request.siteURL)
            flowStatus = .running("Waiting for search controls")
            progress?("Waiting for the visible OpenTable search controls.")

            let inspection = try await waitForSearchField(timeout: 10)
            lastInspection = inspection

            flowStatus = .running("Filling search field")
            progress?("Filling the restaurant search field with \(request.query).")
            _ = try await performRetriedAsyncAction(
                name: "fill_search",
                detail: request.query,
                policy: RetryPolicy(attempts: 3, delay: 0.6)
            ) {
                try await self.evaluateJSONScript(ChromiumBrowserScripts.fillVisibleSearchField(query: request.query))
            } shouldRetry: { _ in
                false
            }

            flowStatus = .running("Submitting search")
            progress?("Submitting the restaurant search.")
            let baselineURL = state.urlString
            let baselineTitle = state.title
            _ = try await performRetriedAsyncAction(
                name: "submit_search",
                detail: request.query,
                policy: RetryPolicy(attempts: 3, delay: 1.0)
            ) {
                try await self.evaluateJSONScript(ChromiumBrowserScripts.submitVisibleSearch)
            } shouldRetry: { [weak self] _ in
                guard let self else { return true }
                return !(try await self.waitForSearchResponse(
                    venueName: request.venueName,
                    previousURL: baselineURL,
                    previousTitle: baselineTitle,
                    timeout: 4
                ))
            }

            flowStatus = .running("Waiting for exact match")
            progress?("Waiting for the exact restaurant result to appear.")
            _ = try await waitForVisibleText(request.venueName, timeout: 8)

            flowStatus = .running("Opening exact result")
            progress?("Opening the exact result for \(request.venueName).")
            let resultBaselineURL = state.urlString
            let resultBaselineTitle = state.title
            _ = try await performRetriedAsyncAction(
                name: "open_exact_result",
                detail: request.venueName,
                policy: RetryPolicy(attempts: 3, delay: 1.0)
            ) {
                try await self.evaluateJSONScript(
                    ChromiumBrowserScripts.clickBestRestaurantMatch(
                        venueName: request.venueName,
                        locationHint: request.locationHint
                    )
                )
            } shouldRetry: { [weak self] _ in
                guard let self else { return true }
                return !(try await self.waitForDestinationPage(
                    venueName: request.venueName,
                    locationHint: request.locationHint,
                    previousURL: resultBaselineURL,
                    previousTitle: resultBaselineTitle,
                    timeout: 5
                ))
            }

            let result = ChromiumRestaurantFlowResult(
                venueName: request.venueName,
                locationHint: request.locationHint,
                finalURL: state.urlString,
                finalTitle: state.title
            )
            flowStatus = .succeeded("Opened \(request.venueName)")
            appendLog("Deterministic restaurant flow completed successfully.")
            progress?("Opened the exact OpenTable page for \(request.venueName).")
            return result
        } catch {
            let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
            flowStatus = .failed(message)
            appendLog("Restaurant flow failed: \(message)")
            progress?("The embedded Chromium flow failed: \(message)")
            throw (error as? ChromiumBrowserActionError) ?? ChromiumBrowserActionError(message: message)
        }
    }

    func runRestaurantBookingFlow(
        request: ChromiumRestaurantBookingRequest,
        progress: ((String) -> Void)? = nil
    ) async throws -> ChromiumRestaurantBookingFlowResult {
        let venue = try await runRestaurantSearchFlow(request: request.searchRequest, progress: progress)
        progress?("Inspecting the OpenTable venue page for reservation controls.")
        var inspection = try await inspectCurrentPageForAgent()
        try await waitForPageToSettle(timeout: 5)

        var selectedPartySize: String?
        var selectedDate: String?
        var selectedTime: String?
        var selectedSlot: String?

        if let partySize = request.parameters.partySize {
            progress?("Setting party size to \(partySize).")
            let valueJSON = try await performRetriedAsyncAction(
                name: "opentable_party_size",
                detail: "\(partySize)",
                policy: RetryPolicy(attempts: 2, delay: 0.8)
            ) {
                try await self.evaluateJSONScript(
                    ChromiumBrowserScripts.selectOpenTablePartySize(partySize),
                    label: "Select OpenTable party size"
                )
            } shouldRetry: { _ in
                try await self.waitForPageToSettle(timeout: 4)
                return false
            }
            selectedPartySize = parseSelectionLabel(from: valueJSON)
            inspection = try await inspectCurrentPageForAgent()
        }

        if let dateText = request.parameters.dateText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dateText.isEmpty {
            progress?("Selecting date \(dateText).")
            let valueJSON = try await performRetriedAsyncAction(
                name: "opentable_date",
                detail: dateText,
                policy: RetryPolicy(attempts: 2, delay: 0.8)
            ) {
                try await self.evaluateJSONScript(
                    ChromiumBrowserScripts.selectOpenTableDate(dateText),
                    label: "Select OpenTable date"
                )
            } shouldRetry: { _ in
                try await self.waitForPageToSettle(timeout: 4)
                return false
            }
            selectedDate = parseSelectionLabel(from: valueJSON) ?? dateText
            inspection = try await inspectCurrentPageForAgent()
        }

        if let timeText = request.parameters.timeText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timeText.isEmpty {
            progress?("Selecting time \(timeText).")
            let valueJSON = try await performRetriedAsyncAction(
                name: "opentable_time",
                detail: timeText,
                policy: RetryPolicy(attempts: 2, delay: 0.8)
            ) {
                try await self.evaluateJSONScript(
                    ChromiumBrowserScripts.selectOpenTableTime(timeText),
                    label: "Select OpenTable time"
                )
            } shouldRetry: { _ in
                try await self.waitForPageToSettle(timeout: 4)
                return false
            }
            selectedTime = parseSelectionLabel(from: valueJSON) ?? timeText
            inspection = try await inspectCurrentPageForAgent()
        }

        progress?("Selecting the best available reservation slot.")
        let slotJSON = try await performRetriedAsyncAction(
            name: "opentable_slot",
            detail: request.parameters.timeText ?? "best available",
            policy: RetryPolicy(attempts: 2, delay: 1.0)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.clickBestOpenTableSlot(preferredTime: request.parameters.timeText),
                label: "Click best OpenTable slot"
            )
        } shouldRetry: { _ in
            try await self.waitForPageToSettle(timeout: 5)
            return false
        }
        selectedSlot = parseSelectionLabel(from: slotJSON)
        inspection = try await inspectCurrentPageForAgent()

        let confirmationButtons = inspection.booking?.confirmationButtons ?? []
        flowStatus = .succeeded("Reached the confirmation boundary for \(venue.venueName)")
        appendLog("Stopped before final confirmation on the OpenTable venue flow.")
        progress?("Stopped before final confirmation. Approval is still required for any final reserve or confirm action.")

        return ChromiumRestaurantBookingFlowResult(
            venueName: venue.venueName,
            finalURL: state.urlString,
            finalTitle: state.title,
            selectedDate: selectedDate,
            selectedTime: selectedTime,
            selectedPartySize: selectedPartySize,
            selectedSlot: selectedSlot,
            confirmationButtons: confirmationButtons
        )
    }

    func browserSnapshot() -> ChromiumBrowserState {
        state
    }

    func browserDebugArtifacts() -> ChromiumBrowserDebugArtifacts {
        ChromiumBrowserDebugArtifacts(
            state: state,
            lastInspection: lastInspection,
            actionTrace: actionTrace,
            snapshots: snapshots,
            flowStatusSummary: flowStatusSummary(),
            approvalStatusSummary: approvalStatusSummary()
        )
    }

    func prepareForShutdown() {
        browserView.prepareForShutdown()
        syncStateFromView()
    }

    func resetBrowserView() {
        browserView.delegate = nil
        browserView = AHChromiumBrowserView(frame: .zero)
        browserView.delegate = self
        browserViewIdentity = UUID()
        lastSyncedBrowserURL = "about:blank"
        syncStateFromView()
    }

    func openURLForAgent(_ url: String) async throws -> ChromiumBrowserState {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw ChromiumBrowserActionError(message: "Open URL requires a non-empty URL.")
        }
        try await openURLAndWaitUntilReady(trimmedURL)
        return state
    }

    func inspectCurrentPageForAgent() async throws -> ChromiumInspection {
        let valueJSON = try await evaluateJSONScript(ChromiumBrowserScripts.inspectPage, label: "Inspect current page")
        let inspection = try decode(ChromiumInspection.self, from: valueJSON)
        lastInspection = inspection
        appendLog("Inspection captured \(inspection.interactiveElements.count) interactive elements.")
        return inspection
    }

    func typeTextForAgent(_ text: String, selector: String) async throws -> String {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else {
            throw ChromiumBrowserActionError(message: "Type text requires a selector.")
        }
        let result = try await performRetriedAsyncAction(
            name: "type_text",
            detail: "\(trimmedSelector) <= \(text)",
            policy: RetryPolicy(attempts: 2, delay: 0.5)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.typeText(text, selector: trimmedSelector),
                label: "Type text for agent"
            )
        } shouldRetry: { _ in
            false
        }
        appendLog("Typed text into \(trimmedSelector).")
        return result
    }

    func typeVerificationCodeForAgent(_ code: String) async throws -> String {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw ChromiumBrowserActionError(message: "Verification code requires a non-empty value.")
        }
        _ = try? await prepareVerificationCodeAutofillForAgent()
        let result = try await performRetriedAsyncAction(
            name: "type_verification_code",
            detail: trimmedCode,
            policy: RetryPolicy(attempts: 3, delay: 0.5)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.typeVerificationCode(trimmedCode),
                label: "Type verification code for agent"
            )
        } shouldRetry: { _ in
            false
        }
        appendLog("Entered verification code into the current browser page.")
        return result
    }

    func prepareVerificationCodeAutofillForAgent() async throws -> String {
        await MainActor.run {
            browserView.focusBrowser()
        }
        _ = try await performRetriedAsyncAction(
            name: "prepare_verification_autofill",
            detail: "Focus one-time-code field",
            policy: RetryPolicy(attempts: 2, delay: 0.2)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.prepareVerificationCodeAutofill,
                label: "Prepare verification code autofill for agent"
            )
        } shouldRetry: { _ in
            false
        }
        let nativeFocusDetails = await MainActor.run {
            browserView.prepareForNativeVerificationAutofill()
        }
        guard Self.nativeVerificationAutofillReady(nativeFocusDetails) else {
            throw ChromiumBrowserActionError(message: "Verification field could not be focused for native autofill.")
        }
        let verifiedResult = try await evaluateJSONScript(
            ChromiumBrowserScripts.prepareVerificationCodeAutofill,
            label: "Verify verification code autofill focus for agent"
        )
        appendLog("Prepared the verification field for native one-time-code autofill.")
        if let nativeFocusDetails,
           let data = try? JSONSerialization.data(withJSONObject: nativeFocusDetails, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8),
           !json.isEmpty {
            return "\(verifiedResult) \(json)"
        }
        return verifiedResult
    }

    func advanceVerificationStepForAgent() async throws -> String {
        let result = try await performRetriedAsyncAction(
            name: "advance_verification_step",
            detail: "Continue verification flow",
            policy: RetryPolicy(attempts: 2, delay: 0.2)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.advanceVerificationStep,
                label: "Advance verification step for agent"
            )
        } shouldRetry: { _ in
            false
        }
        appendLog("Advanced the verification step in the current browser page.")
        return result
    }

    func selectOptionForAgent(_ text: String, selector: String) async throws -> String {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else {
            throw ChromiumBrowserActionError(message: "Select option requires a selector.")
        }
        guard !trimmedText.isEmpty else {
            throw ChromiumBrowserActionError(message: "Select option requires option text.")
        }
        let result = try await performRetriedAsyncAction(
            name: "select_option",
            detail: "\(trimmedSelector) => \(trimmedText)",
            policy: RetryPolicy(attempts: 2, delay: 0.4)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.selectOption(selector: trimmedSelector, text: trimmedText),
                label: "Select option for agent"
            )
        } shouldRetry: { _ in
            false
        }
        appendLog("Selected option \(trimmedText) in \(trimmedSelector).")
        return result
    }

    func chooseAutocompleteOptionForAgent(_ text: String, selector: String?) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ChromiumBrowserActionError(message: "Autocomplete selection requires option text.")
        }
        let result = try await performRetriedAsyncAction(
            name: "choose_autocomplete_option",
            detail: "\(trimmedSelector ?? "active input") => \(trimmedText)",
            policy: RetryPolicy(attempts: 2, delay: 0.5)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.chooseAutocompleteOption(selector: trimmedSelector, text: trimmedText),
                label: "Choose autocomplete option for agent"
            )
        } shouldRetry: { _ in
            try await self.waitForPageToSettle(timeout: 2)
            return false
        }
        appendLog("Chose autocomplete option \(trimmedText).")
        return result
    }

    func chooseGroupedOptionForAgent(_ text: String, groupLabel: String?, selector: String?) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGroupLabel = groupLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ChromiumBrowserActionError(message: "Grouped option selection requires option text.")
        }
        let result = try await performRetriedAsyncAction(
            name: "choose_grouped_option",
            detail: "\(trimmedGroupLabel ?? trimmedSelector ?? "best group") => \(trimmedText)",
            policy: RetryPolicy(attempts: 2, delay: 0.5)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.chooseGroupedOption(
                    selector: trimmedSelector,
                    groupLabel: trimmedGroupLabel,
                    text: trimmedText
                ),
                label: "Choose grouped option for agent"
            )
        } shouldRetry: { _ in
            try await self.waitForPageToSettle(timeout: 2)
            return false
        }
        appendLog("Chose grouped option \(trimmedText).")
        return result
    }

    func pickDateForAgent(_ text: String, selector: String?) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ChromiumBrowserActionError(message: "Pick date requires a target date string.")
        }
        let result = try await performRetriedAsyncAction(
            name: "pick_date",
            detail: "\(trimmedSelector ?? "best date control") => \(trimmedText)",
            policy: RetryPolicy(attempts: 2, delay: 0.7)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.pickDate(selector: trimmedSelector, text: trimmedText),
                label: "Pick date for agent"
            )
        } shouldRetry: { _ in
            try await self.waitForPageToSettle(timeout: 2)
            return false
        }
        appendLog("Picked date \(trimmedText).")
        return result
    }

    func submitFormForAgent(selector: String?, label: String?, transactionalKind: String? = nil, requireApproval: Bool = true) async throws -> String {
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmedLabel ?? trimmedSelector ?? "best matching form"
        if requireApproval {
            try await requestApprovalIfNeeded(
                actionName: "submit_form",
                detail: detail,
                rationale: "Submitting a form may trigger a booking, checkout, or confirmation step.",
                transactionalKind: transactionalKind
            )
        }
        let baselineInspection = lastInspection
        let result = try await performRetriedAsyncAction(
            name: "submit_form",
            detail: detail,
            policy: RetryPolicy(attempts: 3, delay: 0.8)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.submitForm(selector: trimmedSelector, label: trimmedLabel),
                label: "Submit form for agent"
            )
        } shouldRetry: { [weak self] _ in
            guard let self else { return false }
            try await self.waitForPageToSettle(timeout: 2)
            if try await self.didPageProgress(from: baselineInspection) {
                return false
            }
            return false
        }
        appendLog("Submitted form \(detail).")
        return result
    }

    func clickSelectorForAgent(_ selector: String, label: String? = nil, transactionalKind: String? = nil, requireApproval: Bool = true) async throws -> String {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else {
            throw ChromiumBrowserActionError(message: "Click selector requires a selector.")
        }
        let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (normalizedLabel?.isEmpty == false ? normalizedLabel : nil) ?? trimmedSelector
        if requireApproval {
            try await requestApprovalIfNeeded(
                actionName: "click_selector",
                detail: detail,
                rationale: "This selector click may trigger a booking, checkout, or confirmation action.",
                transactionalKind: transactionalKind
            )
        }
        let baselineURL = state.urlString
        let baselineTitle = state.title
        let baselineInspection = lastInspection
        let result = try await performRetriedAsyncAction(
            name: "click_selector",
            detail: trimmedSelector,
            policy: RetryPolicy(attempts: 3, delay: 0.8)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.clickSelector(trimmedSelector),
                label: "Click selector for agent"
            )
        } shouldRetry: { [weak self] _ in
            guard let self else { return true }
            if self.didPageRespond(afterSubmittingFromURL: baselineURL, title: baselineTitle) {
                return false
            }
            do {
                try await self.waitForPageToSettle(timeout: 6)
            } catch {
                if self.didPageRespond(afterSubmittingFromURL: baselineURL, title: baselineTitle) {
                    return false
                }
                throw error
            }
            if try await self.didPageProgress(from: baselineInspection) {
                return false
            }
            return false
        }
        appendLog("Clicked selector \(detail).")
        return result
    }

    func clickTextForAgent(_ text: String, label: String? = nil, transactionalKind: String? = nil, requireApproval: Bool = true) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ChromiumBrowserActionError(message: "Click text requires visible text.")
        }
        let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (normalizedLabel?.isEmpty == false ? normalizedLabel : nil) ?? trimmedText
        if requireApproval {
            try await requestApprovalIfNeeded(
                actionName: "click_text",
                detail: detail,
                rationale: "This click may trigger a booking, checkout, or confirmation action.",
                transactionalKind: transactionalKind
            )
        }
        let baselineInspection = lastInspection
        let result = try await performRetriedAsyncAction(
            name: "click_text",
            detail: trimmedText,
            policy: RetryPolicy(attempts: 3, delay: 0.8)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.clickElementContainingText(trimmedText),
                label: "Click text for agent"
            )
        } shouldRetry: { [weak self] _ in
            guard let self else { return false }
            do {
                try await self.waitForPageToSettle(timeout: 6)
            } catch {
                if self.state.isLoading {
                    return false
                }
                throw error
            }
            if try await self.didPageProgress(from: baselineInspection) {
                return false
            }
            return false
        }
        appendLog("Clicked visible text match \(detail).")
        return result
    }

    func pressKeyForAgent(_ key: String) async throws -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ChromiumBrowserActionError(message: "Press key requires a key.")
        }
        let result = try await performRetriedAsyncAction(
            name: "press_key",
            detail: trimmedKey,
            policy: RetryPolicy(attempts: 2, delay: 0.4)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.pressKey(trimmedKey),
                label: "Press key for agent"
            )
        } shouldRetry: { _ in
            false
        }
        appendLog("Pressed key \(trimmedKey).")
        return result
    }

    func scrollForAgent(deltaY: Double) async throws -> String {
        let result = try await performRetriedAsyncAction(
            name: "scroll",
            detail: "deltaY=\(deltaY)",
            policy: RetryPolicy(attempts: 2, delay: 0.3)
        ) {
            try await self.evaluateJSONScript(
                ChromiumBrowserScripts.scrollBy(deltaY: deltaY),
                label: "Scroll for agent"
            )
        } shouldRetry: { _ in
            false
        }
        appendLog("Scrolled by \(Int(deltaY)).")
        return result
    }

    func waitForTextForAgent(_ text: String, timeout: TimeInterval) async throws -> VisibleTextProbe {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ChromiumBrowserActionError(message: "Wait for text requires text.")
        }
        guard let probe = try await waitForVisibleText(trimmedText, timeout: timeout) else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for visible text \(trimmedText).")
        }
        appendLog("Observed visible text match \(trimmedText).")
        return probe
    }

    func waitForSelectorForAgent(_ selector: String, timeout: TimeInterval) async throws -> ChromiumSelectorProbe {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else {
            throw ChromiumBrowserActionError(message: "Wait for selector requires a selector.")
        }
        var latestProbe: ChromiumSelectorProbe?
        try await waitUntil(name: "selector \(trimmedSelector)", timeout: timeout) { [weak self] in
            guard let self else { return false }
            let valueJSON = try await self.evaluateJSONScript(
                ChromiumBrowserScripts.probeSelector(trimmedSelector),
                label: "Probe selector"
            )
            let probe = try self.decode(ChromiumSelectorProbe.self, from: valueJSON)
            latestProbe = probe
            return probe.found
        }
        guard let latestProbe else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for selector \(trimmedSelector).")
        }
        appendLog("Observed selector \(trimmedSelector).")
        return latestProbe
    }

    func waitForNavigationForAgent(expectedURLFragment: String?, timeout: TimeInterval) async throws -> ChromiumSelectorProbe {
        let previousURL = state.urlString
        let previousTitle = state.title
        let expectedFragment = expectedURLFragment?.trimmingCharacters(in: .whitespacesAndNewlines)
        var latestProbe: ChromiumSelectorProbe?
        try await waitUntil(name: "navigation", timeout: timeout) { [weak self] in
            guard let self else { return false }
            let valueJSON = try await self.evaluateJSONScript(
                ChromiumBrowserScripts.navigationProbe(
                    previousURL: previousURL,
                    previousTitle: previousTitle,
                    expectedURLFragment: expectedFragment
                ),
                label: "Probe navigation"
            )
            let probe = try self.decode(ChromiumSelectorProbe.self, from: valueJSON)
            latestProbe = probe
            return probe.found
        }
        guard let latestProbe else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for navigation.")
        }
        appendLog("Observed navigation to \(latestProbe.url).")
        return latestProbe
    }

    func waitForResultsForAgent(expectedText: String?, timeout: TimeInterval) async throws -> ChromiumResultsProbe {
        let trimmedText = expectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        var latestProbe: ChromiumResultsProbe?
        try await waitUntil(name: "results", timeout: timeout) { [weak self] in
            guard let self else { return false }
            let valueJSON = try await self.evaluateJSONScript(
                ChromiumBrowserScripts.resultsProbe(expectedText: trimmedText),
                label: "Probe results"
            )
            let probe = try self.decode(ChromiumResultsProbe.self, from: valueJSON)
            latestProbe = probe
            return probe.found
        }
        guard let latestProbe else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for search results.")
        }
        appendLog("Observed \(latestProbe.resultCount) visible results.")
        return latestProbe
    }

    func waitForDialogForAgent(expectedText: String?, timeout: TimeInterval) async throws -> ChromiumDialogProbe {
        let trimmedText = expectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        var latestProbe: ChromiumDialogProbe?
        try await waitUntil(name: "dialog", timeout: timeout) { [weak self] in
            guard let self else { return false }
            let valueJSON = try await self.evaluateJSONScript(
                ChromiumBrowserScripts.dialogProbe(expectedText: trimmedText),
                label: "Probe dialog"
            )
            let probe = try self.decode(ChromiumDialogProbe.self, from: valueJSON)
            latestProbe = probe
            return probe.found
        }
        guard let latestProbe else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for dialog.")
        }
        appendLog("Observed dialog \(latestProbe.label).")
        return latestProbe
    }

    func waitForSettleForAgent(timeout: TimeInterval) async throws -> ChromiumBrowserState {
        try await waitForPageToSettle(timeout: timeout)
        appendLog("Page settled at \(state.urlString).")
        return state
    }

    func settlePageForAgent(timeout: TimeInterval) async throws {
        try await waitForPageToSettle(timeout: timeout)
        appendLog("Settled current page before follow-up inspection.")
    }

    func captureSnapshotForAgent(label: String?) async throws -> ChromiumSnapshotArtifact {
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try await captureSnapshot(label: trimmedLabel.isEmpty ? "agent" : trimmedLabel)
    }

    func captureScrolledSnapshotForAgent(label: String?) async throws -> ChromiumSnapshotArtifact {
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try await captureScrolledSnapshot(label: trimmedLabel.isEmpty ? "agent-scroll" : trimmedLabel)
    }

    func setAddressBarEditing(_ isEditing: Bool) {
        isEditingAddressBar = isEditing
        if !isEditing {
            syncAddressBarFromBrowserIfNeeded()
        }
    }

    func goBack() {
        browserView.goBack()
    }

    func goForward() {
        browserView.goForward()
    }

    func reload() {
        browserView.reloadPage()
    }

    func stop() {
        browserView.stopLoading()
    }

    func inspectPage() {
        evaluate(script: ChromiumBrowserScripts.inspectPage, label: "Inspect page") { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(valueJSON):
                do {
                    let inspection = try self.decode(ChromiumInspection.self, from: valueJSON)
                    self.lastInspection = inspection
                    self.appendLog("Inspection captured \(inspection.interactiveElements.count) interactive elements.")
                } catch {
                    self.appendLog("Inspection parse failed: \(error.localizedDescription)")
                    self.state.lastErrorMessage = "Failed to parse inspection output."
                }
            case let .failure(error):
                self.appendLog("Inspection failed: \(error.message)")
                self.state.lastErrorMessage = error.message
            }
        }
    }

    func captureSnapshot() {
        Task {
            do {
                _ = try await captureScrolledSnapshot(label: "manual")
            } catch {
                let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                appendLog("Snapshot failed: \(message)")
                state.lastErrorMessage = message
            }
        }
    }

    func approvePendingAction() {
        guard case let .pending(pending) = approvalStatus else { return }
        lastApprovalDecision = true
        approvalStatus = .idle
        appendLog("Approved pending browser action: \(pending.actionName)")
    }

    func rejectPendingAction() {
        guard case let .pending(pending) = approvalStatus else { return }
        lastApprovalDecision = false
        approvalStatus = .idle
        flowStatus = .failed("Rejected action: \(pending.detail)")
        appendLog("Rejected pending browser action: \(pending.actionName)")
    }

    func fillVisibleSearchField() {
        let query = quickSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        performRetriedAction(
            label: "Fill visible search field",
            successPrefix: "Filled visible search field.",
            policy: RetryPolicy(attempts: 3, delay: 0.6),
            script: { ChromiumBrowserScripts.fillVisibleSearchField(query: query) },
            shouldRetry: { result in
                if case .failure = result { return true }
                return false
            }
        ) { [weak self] result in
            self?.handleGenericResult(result, successPrefix: "Filled visible search field.")
        }
    }

    func submitVisibleSearch() {
        let previousURL = state.urlString
        let previousTitle = state.title
        performRetriedAction(
            label: "Submit visible search",
            successPrefix: "Submitted visible search.",
            policy: RetryPolicy(attempts: 3, delay: 0.9),
            script: { ChromiumBrowserScripts.submitVisibleSearch },
            shouldRetry: { [weak self] result in
                guard case .success = result else { return true }
                guard let self else { return true }
                return !self.didPageRespond(afterSubmittingFromURL: previousURL, title: previousTitle)
            }
        ) { [weak self] result in
            self?.handleGenericResult(result, successPrefix: "Submitted visible search.")
        }
    }

    func clickMatchingText() {
        let trimmed = textMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                try await requestApprovalIfNeeded(
                    actionName: "click_text_match",
                    detail: trimmed,
                    rationale: "This click may trigger a booking or checkout action."
                )
                let previousURL = state.urlString
                let previousTitle = state.title
                let _ = try await performRetriedAsyncAction(
                    name: "click_text_match",
                    detail: trimmed,
                    policy: RetryPolicy(attempts: 3, delay: 0.9)
                ) {
                    try await self.evaluateJSONScript(ChromiumBrowserScripts.clickElementContainingText(trimmed))
                } shouldRetry: { [weak self] _ in
                    guard let self else { return true }
                    return !self.didPageRespond(afterSubmittingFromURL: previousURL, title: previousTitle)
                }
                appendLog("Clicked a visible text match.")
            } catch {
                let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                appendLog(message)
                state.lastErrorMessage = message
            }
        }
    }

    func typeIntoSelector() {
        let selector = selectorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { return }
        evaluate(script: ChromiumBrowserScripts.typeText(selectorInputText, selector: selector),
                 label: "Type into selector") { [weak self] result in
            self?.handleGenericResult(result, successPrefix: "Typed into selector.")
        }
    }

    func clickSelector() {
        let selector = selectorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { return }
        Task {
            do {
                try await requestApprovalIfNeeded(
                    actionName: "click_selector",
                    detail: selector,
                    rationale: "This selector click may trigger a transactional browser action."
                )
                let _ = try await evaluateJSONScript(
                    ChromiumBrowserScripts.clickSelector(selector),
                    label: "Click selector"
                )
                appendLog("Clicked selector.")
            } catch {
                let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                appendLog(message)
                state.lastErrorMessage = message
            }
        }
    }

    private func evaluate(script: String,
                          label: String,
                          completion: @escaping (Result<String, ChromiumBrowserActionError>) -> Void) {
        appendLog(label)
        browserView.evaluateJavaScript(script) { valueJSON, errorMessage in
            Task { @MainActor in
                if let errorMessage {
                    completion(.failure(.init(message: errorMessage)))
                } else {
                    completion(.success(valueJSON ?? "null"))
                }
            }
        }
    }

    private func evaluateAsync(script: String, label: String) async -> Result<String, ChromiumBrowserActionError> {
        await withCheckedContinuation { continuation in
            evaluate(script: script, label: label) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func evaluateJSONScript(_ script: String, label: String? = nil) async throws -> String {
        let result = await evaluateAsync(script: script, label: label ?? "Evaluate script")
        switch result {
        case let .success(valueJSON):
            return valueJSON
        case let .failure(error):
            throw error
        }
    }

    private func performRetriedAction(label: String,
                                      successPrefix: String,
                                      policy: RetryPolicy,
                                      script: @escaping () -> String,
                                      shouldRetry: @escaping (Result<String, ChromiumBrowserActionError>) -> Bool,
                                      completion: @escaping (Result<String, ChromiumBrowserActionError>) -> Void) {
        func attempt(_ currentAttempt: Int) {
            let attemptLabel = policy.attempts > 1 ? "\(label) (attempt \(currentAttempt)/\(policy.attempts))" : label
            evaluate(script: script(), label: attemptLabel) { [weak self] result in
                guard let self else { return }
                if currentAttempt < policy.attempts && shouldRetry(result) {
                    self.appendLog("No reliable page response yet. Retrying \(label.lowercased()).")
                    DispatchQueue.main.asyncAfter(deadline: .now() + policy.delay) {
                        attempt(currentAttempt + 1)
                    }
                    return
                }
                completion(result)
            }
        }

        attempt(1)
    }

    private func performRetriedAsyncAction(name: String,
                                           detail: String,
                                           policy: RetryPolicy,
                                           action: @escaping () async throws -> String,
                                           shouldRetry: @escaping (String) async throws -> Bool) async throws -> String {
        var lastError: Error?

        for attempt in 1...policy.attempts {
            recordTrace(name: name, detail: detail, status: .running, attempt: attempt)
            do {
                let value = try await action()
                if attempt < policy.attempts, try await shouldRetry(value) {
                    recordTrace(name: name,
                                detail: "No page response after attempt \(attempt).",
                                status: .skipped,
                                attempt: attempt)
                    try await Task.sleep(for: .seconds(policy.delay))
                    continue
                }
                recordTrace(name: name, detail: detail, status: .succeeded, attempt: attempt)
                _ = try? await captureSnapshot(label: "\(name)-success-\(attempt)")
                return value
            } catch {
                lastError = error
                let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                recordTrace(name: name, detail: message, status: .failed, attempt: attempt)
                _ = try? await captureSnapshot(label: "\(name)-failure-\(attempt)")
                if attempt < policy.attempts {
                    try await Task.sleep(for: .seconds(policy.delay))
                }
            }
        }

        throw (lastError as? ChromiumBrowserActionError) ?? ChromiumBrowserActionError(message: lastError?.localizedDescription ?? "Browser action failed.")
    }

    private func recordTrace(name: String, detail: String, status: ChromiumActionStatus, attempt: Int) {
        actionTrace.insert(
            ChromiumActionTraceEntry(name: name, detail: detail, status: status, attempt: attempt, url: state.urlString),
            at: 0
        )
        if actionTrace.count > 40 {
            actionTrace.removeLast(actionTrace.count - 40)
        }
    }

    private func waitUntil(name: String,
                           timeout: TimeInterval,
                           pollInterval: Duration = .milliseconds(250),
                           condition: @escaping @MainActor () async throws -> Bool) async throws {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if try await condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }
        throw ChromiumBrowserActionError(message: "Timed out waiting for \(name).")
    }

    private func waitForPageToSettle(timeout: TimeInterval) async throws {
        try await waitUntil(name: "page settle", timeout: timeout, pollInterval: .milliseconds(300)) { [weak self] in
            guard let self else { return false }
            if self.state.isLoading {
                return false
            }
            let valueJSON = try await self.evaluateJSONScript(
                ChromiumBrowserScripts.retryProbe(previousURL: self.state.urlString, previousTitle: self.state.title),
                label: "Probe page settle"
            )
            let probe = try self.decode(ChromiumRetryProbe.self, from: valueJSON)
            return probe.readyState == "complete"
        }
    }

    private func captureSnapshot(label: String) async throws -> ChromiumSnapshotArtifact {
        let pngData: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            browserView.capturePNGSnapshot { data, errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: ChromiumBrowserActionError(message: errorMessage))
                    return
                }
                guard let data else {
                    continuation.resume(throwing: ChromiumBrowserActionError(message: "No snapshot data was returned."))
                    return
                }
                continuation.resume(returning: data)
            }
        }

        let fileManager = FileManager.default
        let directory = AppPaths.defaultRoot()
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("chromium-snapshots", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitized = label
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fileURL = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(sanitized).png")
        try pngData.write(to: fileURL, options: Data.WritingOptions.atomic)

        let artifact = ChromiumSnapshotArtifact(
            createdAt: Date(),
            label: label,
            filePath: fileURL.path,
            url: state.urlString,
            title: state.title,
            recognizedText: nil
        )
        snapshots.insert(artifact, at: 0)
        if snapshots.count > 20 {
            snapshots.removeLast(snapshots.count - 20)
        }
        appendLog("Captured snapshot: \(fileURL.lastPathComponent)")
        return artifact
    }

    private func captureScrolledSnapshot(label: String) async throws -> ChromiumSnapshotArtifact {
        let planJSON = try await evaluateJSONScript(ChromiumBrowserScripts.beginScrollCapture, label: "Begin scrolled snapshot capture")
        let plan = try decode(ScrollCapturePlan.self, from: planJSON)

        var segmentImages: [CGImage] = []
        var recognizedSegments: [String] = []

        defer {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.evaluateJSONScript(
                    ChromiumBrowserScripts.endScrollCapture(restoring: plan.originalOffset),
                    label: "End scrolled snapshot capture"
                )
            }
        }

        for offset in plan.offsets {
            let positionJSON = try await evaluateJSONScript(
                ChromiumBrowserScripts.setScrollCaptureOffset(offset),
                label: "Set scrolled snapshot offset"
            )
            let position = try decode(ScrollCapturePosition.self, from: positionJSON)
            try? await Task.sleep(nanoseconds: 250_000_000)

            let pngData: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                browserView.capturePNGSnapshot { data, errorMessage in
                    if let errorMessage {
                        continuation.resume(throwing: ChromiumBrowserActionError(message: errorMessage))
                        return
                    }
                    guard let data else {
                        continuation.resume(throwing: ChromiumBrowserActionError(message: "No snapshot data was returned."))
                        return
                    }
                    continuation.resume(returning: data)
                }
            }

            guard let segment = croppedSnapshotImage(from: pngData, rect: position.viewportRect) else {
                continue
            }
            segmentImages.append(segment)
            if let recognized = recognizeText(in: segment), !recognized.isEmpty {
                recognizedSegments.append(recognized)
            }
        }

        guard !segmentImages.isEmpty else {
            throw ChromiumBrowserActionError(message: "Failed to capture any scroll snapshot segments.")
        }

        let stitchedImage = stitchSnapshotSegments(segmentImages)
        let pngData = try pngData(for: stitchedImage)

        let fileManager = FileManager.default
        let directory = AppPaths.defaultRoot()
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("chromium-snapshots", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitized = label
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fileURL = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(sanitized)-scroll.png")
        try pngData.write(to: fileURL, options: Data.WritingOptions.atomic)

        let recognizedText = recognizedSegments
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, line in
                guard !result.contains(line) else { return }
                result.append(line)
            }
            .joined(separator: "\n")

        let artifact = ChromiumSnapshotArtifact(
            createdAt: Date(),
            label: label,
            filePath: fileURL.path,
            url: state.urlString,
            title: state.title,
            recognizedText: recognizedText.isEmpty ? nil : recognizedText
        )
        snapshots.insert(artifact, at: 0)
        if snapshots.count > 20 {
            snapshots.removeLast(snapshots.count - 20)
        }
        appendLog("Captured scrolled snapshot: \(fileURL.lastPathComponent)")
        return artifact
    }

    private func croppedSnapshotImage(from pngData: Data, rect: ScrollCaptureRect) -> CGImage? {
        guard let image = NSImage(data: pngData) else { return nil }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let bounds = browserView.bounds
        let scaleX = CGFloat(cgImage.width) / max(bounds.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(bounds.height, 1)
        let cropRect = CGRect(
            x: max(0, CGFloat(rect.x) * scaleX),
            y: max(0, CGFloat(cgImage.height) - ((CGFloat(rect.y) + CGFloat(rect.height)) * scaleY)),
            width: min(CGFloat(cgImage.width), CGFloat(rect.width) * scaleX),
            height: min(CGFloat(cgImage.height), CGFloat(rect.height) * scaleY)
        ).integral

        guard cropRect.width > 2, cropRect.height > 2,
              let cropped = cgImage.cropping(to: cropRect) else {
            return cgImage
        }
        return cropped
    }

    private func stitchSnapshotSegments(_ segments: [CGImage]) -> CGImage {
        let width = segments.map(\.width).max() ?? 1
        let height = segments.reduce(0) { $0 + $1.height }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var currentY = height
        for segment in segments {
            currentY -= segment.height
            context.draw(segment, in: CGRect(x: 0, y: currentY, width: segment.width, height: segment.height))
        }

        return context.makeImage()!
    }

    private func pngData(for image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ChromiumBrowserActionError(message: "Failed to encode the scrolled snapshot.")
        }
        return data
    }

    private func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }
            return lines.joined(separator: "\n")
        } catch {
            appendLog("Scrolled snapshot OCR failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func openURLAndWaitUntilReady(_ url: String) async throws {
        addressBarText = url
        appendLog("Opening \(url)")
        browserView.loadURLString(url)
        try await waitUntil(name: "initial page load", timeout: 10) { [weak self] in
            guard let self else { return false }
            if self.state.isLoading {
                return false
            }
            let currentURL = self.state.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            return currentURL != "about:blank" && !currentURL.isEmpty
        }
        _ = try? await captureSnapshot(label: "open-url")
    }

    private func waitForSearchField(timeout: TimeInterval) async throws -> ChromiumInspection {
        var latestInspection: ChromiumInspection?
        try await waitUntil(name: "visible search field", timeout: timeout, pollInterval: .milliseconds(350)) { [weak self] in
            guard let self else { return false }
            let valueJSON = try await self.evaluateJSONScript(ChromiumBrowserScripts.inspectPage, label: "Inspect for search field")
            let inspection = try self.decode(ChromiumInspection.self, from: valueJSON)
            latestInspection = inspection
            return inspection.hasSearchField
        }
        guard let latestInspection else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for a visible search field.")
        }
        return latestInspection
    }

    private func waitForSearchResponse(venueName: String,
                                       previousURL: String,
                                       previousTitle: String,
                                       timeout: TimeInterval) async throws -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if state.isLoading {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }

            if didPageRespond(afterSubmittingFromURL: previousURL, title: previousTitle) {
                return true
            }

            let valueJSON = try await evaluateJSONScript(
                ChromiumBrowserScripts.retryProbe(previousURL: previousURL, previousTitle: previousTitle),
                label: "Probe page response"
            )
            let probe = try decode(ChromiumRetryProbe.self, from: valueJSON)
            if probe.indicatesPageResponse {
                return true
            }

            let visibleText = try await waitForVisibleText(venueName, timeout: 0.6, allowFailure: true)
            if visibleText != nil {
                return true
            }

            try await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func waitForDestinationPage(venueName: String,
                                        locationHint: String?,
                                        previousURL: String,
                                        previousTitle: String,
                                        timeout: TimeInterval) async throws -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if state.isLoading {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }

            let currentURL = state.urlString.lowercased()
            let currentTitle = state.title.lowercased()
            let needle = venueName.lowercased()
            let slugNeedle = needle.replacingOccurrences(of: " ", with: "-")
            let normalizedLocation = (locationHint ?? "").lowercased()
            if (currentURL != previousURL.lowercased() || currentTitle != previousTitle.lowercased())
                && (currentURL.contains(slugNeedle)
                    || currentTitle.contains(needle))
                && (normalizedLocation.isEmpty
                    || currentURL.contains(normalizedLocation.replacingOccurrences(of: " ", with: "-"))
                    || currentTitle.contains(normalizedLocation)) {
                return true
            }

            if let probe = try await waitForVisibleText(venueName, timeout: 0.6, allowFailure: true),
               probe.matchCount > 0,
               probe.title.lowercased().contains(needle),
               normalizedLocation.isEmpty || probe.firstMatch.contains(normalizedLocation) || probe.title.lowercased().contains(normalizedLocation) {
                return true
            }

            try await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func waitForVisibleText(_ text: String,
                                    timeout: TimeInterval,
                                    allowFailure: Bool = false) async throws -> VisibleTextProbe? {
        var latestProbe: VisibleTextProbe?
        do {
            try await waitUntil(name: "visible text matching \(text)", timeout: timeout) { [weak self] in
                guard let self else { return false }
                let valueJSON = try await self.evaluateJSONScript(
                    ChromiumBrowserScripts.visibleTextProbe(text),
                    label: "Probe visible text"
                )
                let probe = try self.decode(VisibleTextProbe.self, from: valueJSON)
                latestProbe = probe
                return probe.matchCount > 0
            }
            return latestProbe
        } catch {
            if allowFailure {
                return nil
            }
            throw error
        }
    }

    private func didPageRespond(afterSubmittingFromURL previousURL: String, title previousTitle: String) -> Bool {
        if state.isLoading {
            return true
        }

        let currentURL = state.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentURL.isEmpty && currentURL != previousURL {
            return true
        }
        if !currentTitle.isEmpty && currentTitle != previousTitle {
            return true
        }
        return false
    }

    private func didPageProgress(from baselineInspection: ChromiumInspection?) async throws -> Bool {
        let latestInspection = try await inspectCurrentPageForAgent()
        return progressMarker(for: latestInspection) != progressMarker(for: baselineInspection)
    }

    private func progressMarker(for inspection: ChromiumInspection?) -> BrowserProgressMarker {
        let labels = (inspection?.interactiveElements ?? [])
            .prefix(6)
            .map { element in
                let source = element.label.isEmpty ? element.text : element.label
                return source.lowercased()
            }
        return BrowserProgressMarker(url: state.urlString, title: state.title, visibleLabels: labels)
    }

    private func parseSelectionLabel(from valueJSON: String) -> String? {
        guard let data = valueJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let keys = ["label", "value", "control"]
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func handleGenericResult(_ result: Result<String, ChromiumBrowserActionError>, successPrefix: String) {
        switch result {
        case let .success(valueJSON):
            appendLog("\(successPrefix) \(valueJSON)")
        case let .failure(error):
            appendLog(error.message)
            state.lastErrorMessage = error.message
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from valueJSON: String) throws -> T {
        let data = Data(valueJSON.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func appendLog(_ message: String) {
        NSLog("[AgentHub][ChromiumPrototype] %@", message)
        logs.insert(ChromiumLogEntry(message: message), at: 0)
        if logs.count > 30 {
            logs.removeLast(logs.count - 30)
        }
    }

    private func syncStateFromView() {
        state.title = browserView.pageTitle ?? "Chromium Prototype"
        state.urlString = browserView.currentURL ?? "about:blank"
        state.isLoading = browserView.isLoading
        state.canGoBack = browserView.canGoBack
        state.canGoForward = browserView.canGoForward
        state.runtimeReady = browserView.isRuntimeReady
        state.lastErrorMessage = browserView.lastErrorMessage
        syncAddressBarFromBrowserIfNeeded()
    }

    private func syncAddressBarFromBrowserIfNeeded() {
        let browserURL = state.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !browserURL.isEmpty else { return }
        guard browserURL != lastSyncedBrowserURL else { return }
        lastSyncedBrowserURL = browserURL
        guard !isEditingAddressBar else { return }
        addressBarText = browserURL
    }

    private func inferredLocationHint(query: String, venueName: String) -> String? {
        let remaining = query
            .replacingOccurrences(of: venueName, with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return nil }
        return remaining
    }

    private func shouldRequireApproval(
        actionName: String,
        detail: String,
        transactionalKind: String?,
        inspection: ChromiumInspection?
    ) -> Bool {
        BrowserTransactionalGuard.approvalShouldBeRequired(
            actionName: actionName,
            detail: detail,
            transactionalKind: transactionalKind,
            inspection: inspection
        )
    }

    private func requestApprovalIfNeeded(
        actionName: String,
        detail: String,
        rationale: String,
        transactionalKind: String? = nil
    ) async throws {
        guard shouldRequireApproval(
            actionName: actionName,
            detail: detail,
            transactionalKind: transactionalKind,
            inspection: lastInspection
        ) else { return }
        lastApprovalDecision = nil
        let pending = ChromiumPendingApproval(actionName: actionName, detail: detail, rationale: rationale, createdAt: Date())
        approvalStatus = .pending(pending)
        appendLog("Waiting for approval: \(detail)")
        try await waitUntil(name: "browser approval", timeout: 120, pollInterval: .milliseconds(250)) { [weak self] in
            guard let self else { return false }
            return self.lastApprovalDecision != nil
        }
        guard let lastApprovalDecision else {
            throw ChromiumBrowserActionError(message: "Timed out waiting for browser approval.")
        }
        if lastApprovalDecision == false {
            throw ChromiumBrowserActionError(message: "Browser action rejected by user.")
        }
    }

    private func flowStatusSummary() -> String {
        switch flowStatus {
        case .idle:
            return "idle"
        case let .running(message):
            return "running: \(message)"
        case let .succeeded(message):
            return "succeeded: \(message)"
        case let .failed(message):
            return "failed: \(message)"
        }
    }

    private func approvalStatusSummary() -> String {
        switch approvalStatus {
        case .idle:
            return "idle"
        case let .pending(pending):
            return "pending: \(pending.actionName) - \(pending.detail)"
        }
    }
}

extension ChromiumBrowserController: AHChromiumBrowserViewDelegate {
    func browserViewDidUpdateState(_ browserView: AHChromiumBrowserView) {
        DispatchQueue.main.async { [weak self] in
            self?.syncStateFromView()
        }
    }

    func browserView(_ browserView: AHChromiumBrowserView, didLogMessage message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appendLog(message)
            self?.syncStateFromView()
        }
    }

    func browserView(_ browserView: AHChromiumBrowserView, didFailWithErrorMessage errorMessage: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appendLog(errorMessage)
            self?.syncStateFromView()
        }
    }
}
