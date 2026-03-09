//
//  AgentHubTests.swift
//  AgentHubTests
//
//  Created by Timothy Zelinsky on 4/3/2026.
//

import Foundation
import Testing
@testable import AgentHub

struct AgentHubTests {
    @Test
    func taskStoreRoundTripsThreadBackedTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = try TaskStore(paths: paths)

        let task = TaskRecord(
            id: UUID(),
            title: "Bondi rentals",
            instructions: "Check for rentals under $900",
            scheduleType: .dailyAtHHMM,
            scheduleValue: "08:00",
            state: .scheduled,
            codexThreadId: "thread-123",
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: .now,
            updatedAt: .now,
            lastRun: nil,
            nextRun: .now,
            lastError: nil
        )

        try store.upsert(task)
        let loaded = try store.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.codexThreadId == "thread-123")
        #expect(loaded.first?.title == "Bondi rentals")
    }

    @Test
    @MainActor
    func computeNextRunSupportsManualAndInterval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let orchestrator = TaskOrchestrator(
            taskStore: try TaskStore(paths: paths),
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: AppRuntimeConfigStore(paths: paths),
            runtimeFactory: { DummyRuntime() }
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manual = orchestrator.computeNextRun(after: now, scheduleType: TaskScheduleType.manual, scheduleValue: "")
        let interval = orchestrator.computeNextRun(after: now, scheduleType: TaskScheduleType.intervalMinutes, scheduleValue: "30")

        #expect(manual == nil)
        #expect(interval != nil)
        #expect(abs(interval!.timeIntervalSince(now) - 1800) < 1)
    }

    @Test
    func browserRetryProbeIndicatesInteractivePageResponse() throws {
        let probe = ChromiumRetryProbe(
            url: "https://www.opentable.com/sake-house",
            title: "Sake House By Hikari - OpenTable",
            readyState: "complete",
            visibleResultCount: 2,
            hasDialog: false
        )

        #expect(probe.indicatesPageResponse)
    }

    @Test
    func restaurantSearchRequestDefaultsMatchPrototypeInputs() throws {
        let request = ChromiumRestaurantSearchRequest.opentableDefault

        #expect(request.siteURL == "https://www.opentable.com")
        #expect(request.query == "Sake House By Hikari Culver City")
        #expect(request.venueName == "Sake House By Hikari")
        #expect(request.locationHint == "Culver City")
    }

    @Test
    func openTableBookingIntentParsesVenueAndLocation() throws {
        let intent = ChatBrowserIntent.parse("make a reservation for me on opentable. Sake House By Hikari. culver city. march 8. 7pm. 2 people.")

        #expect(intent != nil)
        #expect(intent?.bookingRequested == true)
        #expect(intent?.request.siteURL == "https://www.opentable.com")
        #expect(intent?.request.venueName == "Sake House By Hikari")
        #expect(intent?.request.locationHint == "culver city")
        #expect(intent?.request.query == "Sake House By Hikari culver city")
    }

    @Test
    func openTableNavigationIntentParsesVenueAndLocation() throws {
        let intent = ChatBrowserIntent.parse("navigate to the Sake House By Hikari. culver city. page on open table")

        #expect(intent != nil)
        #expect(intent?.bookingRequested == false)
        #expect(intent?.request.venueName == "Sake House By Hikari")
        #expect(intent?.request.locationHint == "culver city")
    }

    @Test
    func openTableBookingIntentParsesDateTimeAndPartySize() throws {
        let intent = ChatBrowserIntent.parse("book opentable. Sake House By Hikari. culver city. tomorrow. 7:30pm. party of 4.")

        #expect(intent != nil)
        #expect(intent?.bookingParameters.dateText == "tomorrow")
        #expect(intent?.bookingParameters.timeText == "7:30pm")
        #expect(intent?.bookingParameters.partySize == 4)
    }

    @Test
    func openTableBookingIntentPreservesMonthAndDay() throws {
        let intent = ChatBrowserIntent.parse("make a reservation for me on opentable. Sake House By Hikari. culver city. march 9. 7pm. 2 people.")

        #expect(intent?.bookingParameters.dateText == "march 9")
        #expect(intent?.bookingParameters.timeText == "7pm")
        #expect(intent?.bookingParameters.partySize == 2)
    }

    @Test
    func openTableIntentConvertsToGenericBrowserGoal() throws {
        let intent = try #require(ChatBrowserIntent.parse("book opentable. Sake House By Hikari. culver city. tomorrow. 7:30pm. party of 4."))
        let genericIntent = intent.genericBrowserIntent

        #expect(genericIntent.initialURL == "https://www.opentable.com")
        #expect(genericIntent.goalText.lowercased().contains("find sake house by hikari"))
        #expect(genericIntent.goalText.lowercased().contains("stop before the final reservation confirmation step"))
        #expect(genericIntent.goalText.lowercased().contains("tomorrow"))
        #expect(genericIntent.goalText.lowercased().contains("7:30pm"))
        #expect(genericIntent.goalText.lowercased().contains("choose the closest available reservation slot"))
    }

    @Test
    func genericBrowserIntentParsesKnownTravelSite() throws {
        let intent = GenericBrowserChatIntent.parse("book a hotel in tokyo on booking.com for next week")

        #expect(intent != nil)
        guard let intent else {
            Issue.record("Expected a generic browser intent.")
            return
        }
        #expect(intent.initialURL == "https://www.booking.com")
        #expect(intent.goalText.lowercased().contains("tokyo"))
    }

    @Test
    func browserAgentResponseParserExtractsCommandPayload() throws {
        let response = """
        I found the destination field.
        <agenthub_browser_command>{"action":"type_text","selector":null,"text":"Tokyo","url":null,"key":null,"timeoutSeconds":null,"deltaY":null,"label":"Destination","finalResponse":null,"rationale":"Fill the destination field."}</agenthub_browser_command>
        """

        let parsed = BrowserAgentResponseParser.parse(response)

        #expect(parsed.displayText == "I found the destination field.")
        #expect(parsed.command?.action == .typeText)
        #expect(parsed.command?.text == "Tokyo")
        #expect(parsed.command?.label == "Destination")
    }

    @Test
    func browserSemanticResolverRetargetsStaleFieldSelector() throws {
        let command = BrowserAgentCommand(
            action: .typeText,
            url: nil,
            selector: "#destination-old",
            text: "Tokyo",
            key: nil,
            timeoutSeconds: nil,
            deltaY: nil,
            label: "Destination",
            finalResponse: nil,
            rationale: nil
        )

        let staleInspection = sampleInspection(destinationSelector: "#destination-old")
        let refreshedInspection = sampleInspection(destinationSelector: "#destination-new")

        let resolution = BrowserSemanticResolver.bestEffortRetarget(
            command,
            staleInspection: staleInspection,
            refreshedInspection: refreshedInspection
        )

        #expect(resolution?.selector == "#destination-new")
        #expect(resolution?.label == "Destination")
    }

    @Test
    func browserTransactionalGuardAutoStopsAtFinalConfirmationBoundary() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Confirm booking",
                    selector: "#confirm-booking",
                    confidence: 95
                )
            ]
        )

        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "book this hotel in tokyo", inspection: inspection))
        #expect(BrowserTransactionalGuard.stopReason(goalText: "book this hotel in tokyo", inspection: inspection)?.contains("Confirm booking") == true)
    }

    @Test
    func browserTransactionalGuardDoesNotAutoStopForNonTransactionalGoal() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Confirm booking",
                    selector: "#confirm-booking",
                    confidence: 95
                )
            ]
        )

        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "inspect this page", inspection: inspection) == false)
    }

    @Test
    func browserTransactionalGuardRequiresApprovalForFinalConfirmationActions() throws {
        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "submit_form",
                detail: "Confirm booking",
                transactionalKind: "final_confirmation"
            )
        )
        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "click_selector",
                detail: "Place order",
                transactionalKind: nil
            )
        )
    }

    @Test
    func browserTransactionalGuardIgnoresReviewOnlyActions() throws {
        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "submit_form",
                detail: "Continue to review",
                transactionalKind: "review_step"
            ) == false
        )
    }

    @Test
    func browserTransactionalGuardAcceptsStrongFinalLabelsEvenBelowConfidenceThreshold() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "review",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Book now",
                    selector: "#book-now",
                    confidence: 70
                )
            ]
        )

        #expect(BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection)?.selector == "#book-now")
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "book this flight", inspection: inspection))
    }

    @Test
    func browserTransactionalGuardIgnoresPromotionalReserveLabels() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Sapphire Reserve Exclusive Tables New cardmembers can book exclusive tables and enjoy a $300 annual dining credit from Chase. Explore restaurants",
                    selector: "a.promo-card",
                    confidence: 90
                )
            ]
        )

        #expect(BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection) == nil)
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "make a reservation on opentable", inspection: inspection) == false)
    }

    @Test
    func browserTransactionalGuardIgnoresFavoriteSaveActions() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Save restaurant to favorites",
                    selector: "button[aria-label='Save restaurant to favorites']",
                    confidence: 95
                )
            ]
        )

        #expect(BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection) == nil)
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "make a reservation on opentable", inspection: inspection) == false)
    }

    @Test
    func browserTransactionalGuardIgnoresDiscoveryListActions() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "View full list View full list View full list",
                    selector: "a.view-full-list",
                    confidence: 95
                )
            ]
        )

        #expect(BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection) == nil)
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "make a reservation on opentable", inspection: inspection) == false)
    }

    @Test
    func browserTransactionalGuardDoesNotAutoStopAtVenueDetailReserveCTA() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Reserve for Others",
                    selector: "button.reserve-for-others",
                    confidence: 95
                )
            ],
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "venue_detail",
                selectedParameterCount: 0,
                hasVenueAction: true,
                hasBookingWidget: false,
                hasSlotSelection: false,
                hasGuestDetailsForm: false,
                hasPaymentForm: false,
                hasReviewSummary: false,
                hasFinalConfirmationBoundary: true,
                selectedDate: false,
                selectedTime: false,
                selectedPartySize: false
            )
        )

        #expect(BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection)?.selector == "button.reserve-for-others")
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "make a reservation on opentable", inspection: inspection) == false)
    }

    @Test
    func browserTransactionalGuardDoesNotAutoStopAtDenseResultsReserveCTA() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "results",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Reserve for Others Reserve for Others",
                    selector: "div.results-card-cta",
                    confidence: 85
                )
            ],
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "results",
                selectedParameterCount: 3,
                hasVenueAction: true,
                hasBookingWidget: true,
                hasSlotSelection: false,
                hasGuestDetailsForm: false,
                hasPaymentForm: false,
                hasReviewSummary: false,
                hasFinalConfirmationBoundary: true,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            )
        )

        #expect(BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection)?.selector == "div.results-card-cta")
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "make a reservation on opentable", inspection: inspection) == false)
    }

    @Test
    func browserTransactionalGuardAutoStopsAtGuestDetailsConfirmationBoundary() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Confirm reservation",
                    selector: "#confirm-reservation",
                    confidence: 95
                )
            ],
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "guest_details",
                selectedParameterCount: 3,
                hasVenueAction: true,
                hasBookingWidget: true,
                hasSlotSelection: true,
                hasGuestDetailsForm: true,
                hasPaymentForm: false,
                hasReviewSummary: false,
                hasFinalConfirmationBoundary: true,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            )
        )

        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "make a reservation on opentable", inspection: inspection))
    }

    @Test
    func browserScenarioClassifierCategorizesTravelAndCheckoutGoals() throws {
        #expect(
            BrowserScenarioClassifier.category(
                forGoalText: "book this restaurant on opentable",
                initialURL: "https://www.opentable.com"
            ) == "restaurant"
        )
        #expect(
            BrowserScenarioClassifier.category(
                forGoalText: "find me a hotel in tokyo",
                initialURL: "https://www.booking.com"
            ) == "hotel"
        )
        #expect(
            BrowserScenarioClassifier.category(
                forGoalText: "search for flights to sydney",
                initialURL: "https://www.google.com/travel/flights"
            ) == "flight"
        )
        #expect(
            BrowserScenarioClassifier.category(
                forGoalText: "stop at the checkout place order step",
                initialURL: "https://www.amazon.com"
            ) == "checkout"
        )
    }

    @Test
    func browserSmokeScenarioManifestLoadsDefinitions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserSmokeManifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("browser-live-smoke-scenarios.json")
        try """
        [
          {
            "id": "example",
            "category": "other",
            "title": "Example",
            "goalText": "open https://example.com and inspect the page",
            "initialURL": "https://example.com",
            "matchAny": ["example.com"],
            "expectedOutcomes": ["completed"],
            "notes": "fixture"
          }
        ]
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let scenarios = try BrowserSmokeScenarioManifest.load(from: fileURL)

        #expect(scenarios.count == 1)
        #expect(scenarios.first?.id == "example")
        #expect(scenarios.first?.expectedOutcomes == ["completed"])
    }

    @Test
    func browserTypeTextScriptUsesNativeValueSetterForControlledInputs() throws {
        let script = ChromiumBrowserScripts.typeText("standard_user", selector: "#user-name")

        #expect(script.contains("nativeValueSetter"))
        #expect(script.contains("Object.getOwnPropertyDescriptor"))
        #expect(script.contains("dispatchTextEntryEvents"))
    }

    @Test
    func browserSearchFillScriptFallsBackToTextboxAndSearchTriggers() throws {
        let script = ChromiumBrowserScripts.fillVisibleSearchField(query: "Sake House By Hikari culver city")

        #expect(script.contains("[role=\"textbox\"]"))
        #expect(script.contains("clickLikelySearchTrigger"))
        #expect(script.contains("editableSelector"))
    }

    @Test
    func browserPickDateScriptMatchesNormalizedCalendarDates() throws {
        let script = ChromiumBrowserScripts.pickDate(selector: "#search-autocomplete-day-picker", text: "2026-03-09")

        #expect(script.contains("parseDateValue"))
        #expect(script.contains("sameCalendarDay"))
        #expect(script.contains("data-date"))
        #expect(script.contains("datetime"))
    }

    @Test
    func browserInspectionScriptIgnoresFavoriteSaveActionsAsFinalConfirmation() throws {
        let script = ChromiumBrowserScripts.inspectPage

        #expect(script.contains("isSavedItemAction"))
        #expect(script.contains("save restaurant to favorites"))
        #expect(script.contains("!isPromotional"))
        #expect(script.contains("!isSavedItemAction"))
    }

    @Test
    func browserInspectionScriptIgnoresDiscoveryListActionsAsFinalConfirmation() throws {
        let script = ChromiumBrowserScripts.inspectPage

        #expect(script.contains("isDiscoveryNavigation"))
        #expect(script.contains("view full list"))
        #expect(script.contains("hasStrongFinalIntent || hasTransactionalContainer || hrefHasTransactionalKeyword"))
    }

    @Test
    func browserInspectionScriptIgnoresDenseResultReserveAndReviewNoise() throws {
        let script = ChromiumBrowserScripts.inspectPage

        #expect(script.contains("isReserveForOthers"))
        #expect(script.contains("isDenseResultAction"))
        #expect(script.contains("transactionalContext"))
        #expect(script.contains("review(?: reservation| booking| details| step| summary)"))
        #expect(script.contains("hasLateStageBookingStructure"))
        #expect(script.contains("isStandaloneControl"))
    }

    @Test
    func browserInspectionScriptPrefersVenueCardOpenActionsOverMapUtilities() throws {
        let script = ChromiumBrowserScripts.inspectPage

        #expect(script.contains("scoreCardActionCandidate"))
        #expect(script.contains("keyboard shortcuts"))
        #expect(script.contains("find next available"))
        #expect(script.contains("candidate.tagName.toLowerCase() === \"a\""))
    }

    @Test
    func browserInspectionScriptEmitsBookingFunnelStage() throws {
        let script = ChromiumBrowserScripts.inspectPage

        #expect(script.contains("const bookingFunnelStage"))
        #expect(script.contains("hasGuestDetailsForm"))
        #expect(script.contains("selectedParameterCount"))
        #expect(script.contains("bookingFunnel"))
        #expect(script.contains("hasDenseResults"))
        #expect(script.contains("transactionalSlotContainer"))
        #expect(script.contains("hasTimeLikeLabel"))
    }

    @Test
    func sampleInspectionSupportsBookingFunnelState() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "review",
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "review",
                selectedParameterCount: 3,
                hasVenueAction: true,
                hasBookingWidget: true,
                hasSlotSelection: true,
                hasGuestDetailsForm: true,
                hasPaymentForm: false,
                hasReviewSummary: true,
                hasFinalConfirmationBoundary: false,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            )
        )

        #expect(inspection.bookingFunnel?.stage == "review")
        #expect(inspection.bookingFunnel?.selectedParameterCount == 3)
        #expect(inspection.bookingFunnel?.hasSlotSelection == true)
    }

    @Test
    func codexRuntimeParsesCurrentThreadStartedEventSchema() throws {
        let runtime = CodexCLIRuntime()

        let parsed = runtime.parseCodexLine(
            #"{"type":"thread.started","thread_id":"thread-123"}"#,
            isStdErr: false
        )

        switch parsed {
        case let .threadId(threadId):
            #expect(threadId == "thread-123")
        default:
            Issue.record("Expected thread.started to produce a thread id event.")
        }
    }

    @Test
    func codexRuntimeParsesCurrentAssistantMessageEventSchema() throws {
        let runtime = CodexCLIRuntime()

        let parsed = runtime.parseCodexLine(
            #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"<agenthub_browser_command>{\"action\":\"inspect_page\",\"selector\":null,\"text\":null,\"url\":null,\"key\":null,\"timeoutSeconds\":null,\"deltaY\":null,\"label\":null,\"finalResponse\":null,\"rationale\":\"Inspect the current page.\"}</agenthub_browser_command>"}}"#,
            isStdErr: false
        )

        switch parsed {
        case let .assistantText(text):
            #expect(
                text
                    == #"<agenthub_browser_command>{"action":"inspect_page","selector":null,"text":null,"url":null,"key":null,"timeoutSeconds":null,"deltaY":null,"label":null,"finalResponse":null,"rationale":"Inspect the current page."}</agenthub_browser_command>"#
            )
        default:
            Issue.record("Expected item.completed to surface assistant text.")
        }
    }
}

private func sampleInspection(
    destinationSelector: String,
    pageStage: String = "form",
    boundaries: [ChromiumTransactionalBoundary] = [],
    bookingFunnel: ChromiumBookingFunnelState? = nil
) -> ChromiumInspection {
    ChromiumInspection(
        title: "Travel Search",
        url: "https://example.com/search",
        pageStage: pageStage,
        formCount: 1,
        hasSearchField: true,
        interactiveElements: [
            ChromiumInteractiveElement(
                id: "element-0",
                role: "input",
                label: "Destination",
                text: "",
                selector: destinationSelector,
                value: nil,
                href: nil,
                purpose: "location",
                groupLabel: "Search form",
                priority: 90
            )
        ],
        forms: [
            ChromiumSemanticForm(
                id: "form-0",
                label: "Search form",
                selector: "form.search",
                submitLabel: "Search",
                fields: [
                    ChromiumSemanticFormField(
                        id: "field-0",
                        label: "Destination",
                        selector: destinationSelector,
                        controlType: "text",
                        value: nil,
                        options: [],
                        isRequired: true
                    )
                ]
            )
        ],
        resultLists: [],
        cards: [],
        dialogs: [],
        controlGroups: [],
        autocompleteSurfaces: [
            ChromiumAutocompleteSurface(
                id: "autocomplete-0",
                label: "Destination",
                inputSelector: destinationSelector,
                optionSelector: "#destination-options",
                options: ["Tokyo", "Sydney"]
            )
        ],
        datePickers: [],
        primaryActions: [],
        transactionalBoundaries: boundaries,
        semanticTargets: [
            ChromiumSemanticTarget(
                id: "target-destination",
                kind: "autocomplete",
                label: "Destination",
                selector: destinationSelector,
                purpose: "location",
                groupLabel: "Search form",
                transactionalKind: nil,
                priority: 95
            )
        ],
        booking: nil,
        bookingFunnel: bookingFunnel
    )
}

private struct DummyRuntime: CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: "dummy", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
