import AppKit
import Combine
import Foundation

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

    private struct VisibleTextProbe: Decodable {
        let url: String
        let title: String
        let matchCount: Int
        let firstMatch: String
    }

    @Published private(set) var state = ChromiumBrowserState()
    @Published private(set) var lastInspection: ChromiumInspection?
    @Published private(set) var logs: [ChromiumLogEntry] = []
    @Published private(set) var actionTrace: [ChromiumActionTraceEntry] = []
    @Published private(set) var snapshots: [ChromiumSnapshotArtifact] = []
    @Published private(set) var flowStatus: ChromiumFlowStatus = .idle
    @Published private(set) var approvalStatus: ChromiumApprovalStatus = .idle

    @Published var addressBarText = "https://www.opentable.com"
    @Published var quickSearchText = "Sake House By Hikari Culver City"
    @Published var textMatch = "Sake House By Hikari"
    @Published var selectorText = ""
    @Published var selectorInputText = ""
    @Published private(set) var isEditingAddressBar = false

    let browserView = AHChromiumBrowserView(frame: .zero)
    private var lastSyncedBrowserURL = "about:blank"
    private var activeRestaurantRequest = ChromiumRestaurantSearchRequest.opentableDefault
    private var lastApprovalDecision: Bool?

    override init() {
        super.init()
        browserView.delegate = self
        browserView.loadURLString(addressBarText)
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
                _ = try await captureSnapshot(label: "manual")
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
            title: state.title
        )
        snapshots.insert(artifact, at: 0)
        if snapshots.count > 20 {
            snapshots.removeLast(snapshots.count - 20)
        }
        appendLog("Captured snapshot: \(fileURL.lastPathComponent)")
        return artifact
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

    private func shouldRequireApproval(actionName: String, detail: String) -> Bool {
        let haystack = "\(actionName) \(detail)".lowercased()
        return haystack.contains("reserve")
            || haystack.contains("book")
            || haystack.contains("checkout")
            || haystack.contains("purchase")
            || haystack.contains("pay")
            || haystack.contains("confirm")
    }

    private func requestApprovalIfNeeded(actionName: String, detail: String, rationale: String) async throws {
        guard shouldRequireApproval(actionName: actionName, detail: detail) else { return }
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
