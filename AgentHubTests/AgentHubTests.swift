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
    func browserApprovalResponseParserRecognizesAffirmativeReplies() throws {
        let yes = try #require(BrowserApprovalResponseParser.parse("yes"))
        #expect(yes.approved)
        #expect(yes.phoneNumber == nil)

        let goAhead = try #require(BrowserApprovalResponseParser.parse("go ahead and do it"))
        #expect(goAhead.approved)
        #expect(goAhead.phoneNumber == nil)

        let reservation = try #require(BrowserApprovalResponseParser.parse("make the reservation"))
        #expect(reservation.approved)
        #expect(reservation.phoneNumber == nil)
    }

    @Test
    func browserApprovalResponseParserRecognizesNegativeReplies() throws {
        let no = try #require(BrowserApprovalResponseParser.parse("no"))
        #expect(no.approved == false)

        let reject = try #require(BrowserApprovalResponseParser.parse("reject it"))
        #expect(reject.approved == false)

        let stop = try #require(BrowserApprovalResponseParser.parse("do not continue"))
        #expect(stop.approved == false)
    }

    @Test
    func browserApprovalResponseParserExtractsPhoneNumber() throws {
        let response = try #require(BrowserApprovalResponseParser.parse("yes using my number 4244134321"))

        #expect(response.approved)
        #expect(response.phoneNumber == "4244134321")
    }

    @Test
    func browserSessionFollowUpParserExtractsVerificationCode() throws {
        let followUp = try #require(BrowserSessionFollowUpParser.parse("use the verification code 957244"))

        #expect(followUp.verificationCode == "957244")
        #expect(followUp.phoneNumber == nil)
    }

    @Test
    func browserSessionFollowUpParserExtractsEmailAndName() throws {
        let followUp = try #require(BrowserSessionFollowUpParser.parse("yes use my email tima@example.com and my name is Tima Zelinsky"))

        #expect(followUp.email == "tima@example.com")
        #expect(followUp.fullName == "Tima Zelinsky")
    }

    @Test
    func browserSessionFollowUpParserExtractsAddressLine2AndConsent() throws {
        let followUp = try #require(BrowserSessionFollowUpParser.parse("apt 4B and yes I agree to the required consent"))

        #expect(followUp.addressLine2 == "4B and yes I agree to the required consent" || followUp.addressLine2 == "4B")
        #expect(followUp.consentDecision == true)
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
        #expect(genericIntent.goalFocusTerms == ["Sake House By Hikari", "culver city"])
        #expect(genericIntent.providedData == nil)
        #expect(genericIntent.goalText.lowercased().contains("first open the exact venue page for sake house by hikari"))
        #expect(genericIntent.goalText.lowercased().contains("stop before the final reservation confirmation step"))
        #expect(genericIntent.goalText.lowercased().contains("tomorrow"))
        #expect(genericIntent.goalText.lowercased().contains("7:30pm"))
        #expect(genericIntent.goalText.lowercased().contains("only after reaching the exact venue page"))
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
    func genericBrowserIntentCapturesInlineProfileData() throws {
        let intent = try #require(GenericBrowserChatIntent.parse("book a hotel in tokyo on booking.com using my email tima@example.com and my number 4244134321"))

        #expect(intent.initialURL == "https://www.booking.com")
        #expect(intent.providedData?.email == "tima@example.com")
        #expect(intent.providedData?.phoneNumber == "4244134321")
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
                transactionalKind: "final_confirmation",
                inspection: nil
            )
        )
        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "click_selector",
                detail: "Place order",
                transactionalKind: nil,
                inspection: nil
            )
        )
    }

    @Test
    func browserTransactionalGuardIgnoresReviewOnlyActions() throws {
        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "submit_form",
                detail: "Continue to review",
                transactionalKind: "review_step",
                inspection: nil
            ) == false
        )
    }

    @Test
    func browserTransactionalGuardDoesNotRequireApprovalForVenuePageSlotSelection() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "results",
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

        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "click_selector",
                detail: "Reserve table at Sake House By Hikari at 7:00 PM on March 9, for a party of 2",
                transactionalKind: "final_confirmation",
                inspection: inspection
            ) == false
        )
    }

    @Test
    func browserTransactionalGuardRequiresApprovalAtReviewStageReservationConfirmation() throws {
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
                hasFinalConfirmationBoundary: true,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            )
        )

        #expect(
            BrowserTransactionalGuard.approvalShouldBeRequired(
                actionName: "click_selector",
                detail: "Confirm reservation",
                transactionalKind: "final_confirmation",
                inspection: inspection
            )
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
    func browserTransactionalGuardIgnoresAuthChoiceActions() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Use email instead",
                    selector: "button.use-email-instead",
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
    func browserSemanticResolverPrefersVisibleReservationSlots() throws {
        let slotTarget = ChromiumSemanticTarget(
            id: "target-slot-0",
            kind: "slot_option",
            label: "Reserve table at Sake House By Hikari at 7:00 PM on March 9, for a party of 2",
            selector: "button.slot-700",
            purpose: "time",
            groupLabel: "available reservation slots",
            transactionalKind: "booking_slot",
            priority: 140
        )
        let genericReserveTarget = ChromiumSemanticTarget(
            id: "target-primary-0",
            kind: "primary_action",
            label: "Reserve for Others",
            selector: "button.reserve-for-others",
            purpose: "confirm",
            groupLabel: nil,
            transactionalKind: "final_confirmation",
            priority: 90
        )
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "results",
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "slot_selection",
                selectedParameterCount: 3,
                hasVenueAction: true,
                hasBookingWidget: true,
                hasSlotSelection: true,
                hasGuestDetailsForm: false,
                hasPaymentForm: false,
                hasReviewSummary: false,
                hasFinalConfirmationBoundary: true,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            ),
            semanticTargets: [genericReserveTarget, slotTarget],
            booking: ChromiumBookingSemanticState(
                partySizeOptions: [],
                dateOptions: [],
                timeOptions: ["7:00 PM"],
                availableSlots: [
                    ChromiumBookingSlot(
                        id: "slot-0",
                        label: slotTarget.label,
                        selector: slotTarget.selector,
                        score: 155
                    )
                ],
                confirmationButtons: [genericReserveTarget.label]
            )
        )

        let resolution = BrowserSemanticResolver.resolve(
            BrowserAgentCommand(
                action: .clickText,
                url: nil,
                selector: nil,
                text: "7:00 PM",
                key: nil,
                timeoutSeconds: nil,
                deltaY: nil,
                label: "7:00 PM reservation slot",
                finalResponse: nil,
                rationale: "Pick the visible reservation slot."
            ),
            inspection: inspection
        )

        #expect(resolution.selector == "button.slot-700")
        #expect(resolution.transactionalKind == "booking_slot")
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
    func browserVerificationAutofillScriptPromotesOneTimeCodeAutocomplete() throws {
        let script = ChromiumBrowserScripts.prepareVerificationCodeAutofill

        #expect(script.contains("one-time-code"))
        #expect(script.contains("inputmode"))
        #expect(script.contains("bestField.click"))
        #expect(script.contains("bestField.focus"))
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
        #expect(script.contains("(labelHasFinalKeyword || hrefHasTransactionalKeyword)"))
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
    func browserInspectionScriptPromotesReviewPageCompleteReservationAsFinalConfirmation() throws {
        let script = ChromiumBrowserScripts.inspectPage

        #expect(script.contains("hasReviewPageSignal"))
        #expect(script.contains("complete(?: booking| order| reservation)?"))
        #expect(script.contains("window.location.pathname"))
        #expect(script.contains("isAccountChoiceAction"))
        #expect(script.contains("use email instead"))
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
        #expect(script.contains("const notices = Array.from"))
        #expect(script.contains("const stepIndicators = Array.from"))
        #expect(script.contains("hasGuestDetailsForm"))
        #expect(script.contains("selectedParameterCount"))
        #expect(script.contains("bookingFunnel"))
        #expect(script.contains("hasDenseResults"))
        #expect(script.contains("transactionalSlotContainer"))
        #expect(script.contains("hasTimeLikeLabel"))
        #expect(script.contains("hasReserveTableLabel"))
        #expect(script.contains("kind: \"slot_option\""))
        #expect(script.contains("transactionalKind: \"booking_slot\""))
        #expect(script.contains("select a time|available times?|choose a time|pick a time"))
        #expect(script.contains("inlineTimeButtonCount"))
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
    func transactionalGuardTreatsCompleteReservationAsHighConfidenceBoundary() throws {
        let inspection = sampleInspection(
            destinationSelector: "#destination",
            pageStage: "final_confirmation",
            boundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Complete reservation",
                    selector: "#complete-reservation",
                    confidence: 70
                )
            ],
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "review",
                selectedParameterCount: 3,
                hasVenueAction: true,
                hasBookingWidget: true,
                hasSlotSelection: true,
                hasGuestDetailsForm: true,
                hasPaymentForm: false,
                hasReviewSummary: true,
                hasFinalConfirmationBoundary: true,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            )
        )

        let boundary = BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection)

        #expect(boundary?.label == "Complete reservation")
        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "Make a reservation for me", inspection: inspection))
    }

    @Test
    func browserTransactionalGuardDoesNotAutoStopDuringVerificationStep() throws {
        let inspection = ChromiumInspection(
            title: "OpenTable - Verify your phone",
            url: "https://www.opentable.com/booking/details",
            pageStage: "final_confirmation",
            formCount: 1,
            hasSearchField: false,
            interactiveElements: [
                ChromiumInteractiveElement(
                    id: "element-0",
                    role: "input",
                    label: "Verification code",
                    text: "",
                selector: "input[name=\"verificationCode\"]",
                value: nil,
                href: nil,
                purpose: nil,
                groupLabel: "Verification",
                isRequired: true,
                isSelected: false,
                validationMessage: nil,
                priority: 95
            )
        ],
            forms: [
                ChromiumSemanticForm(
                    id: "form-0",
                    label: "Verification",
                    selector: "form.verify",
                    submitLabel: "Continue",
                    fields: [
                        ChromiumSemanticFormField(
                            id: "field-0",
                            label: "Verification code",
                            selector: "input[name=\"verificationCode\"]",
                            controlType: "one-time-code",
                            value: nil,
                            options: [],
                            autocomplete: "one-time-code",
                            inputMode: "numeric",
                            fieldPurpose: "verification_code",
                            isRequired: true,
                            isSelected: false,
                            validationMessage: nil
                        )
                    ]
                )
            ],
            resultLists: [],
            cards: [],
            dialogs: [],
            controlGroups: [],
            autocompleteSurfaces: [],
            datePickers: [],
            notices: [],
            stepIndicators: [],
            primaryActions: [
                ChromiumSemanticAction(
                    id: "action-0",
                    label: "Complete reservation",
                    selector: "#complete-reservation",
                    role: "button",
                    priority: 100
                )
            ],
            transactionalBoundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-0",
                    kind: "final_confirmation",
                    label: "Complete reservation",
                    selector: "#complete-reservation",
                    confidence: 95
                )
            ],
            semanticTargets: [],
            booking: nil,
            bookingFunnel: ChromiumBookingFunnelState(
                stage: "review",
                selectedParameterCount: 3,
                hasVenueAction: true,
                hasBookingWidget: true,
                hasSlotSelection: true,
                hasGuestDetailsForm: true,
                hasPaymentForm: false,
                hasReviewSummary: true,
                hasFinalConfirmationBoundary: true,
                selectedDate: true,
                selectedTime: true,
                selectedPartySize: true
            )
        )

        #expect(BrowserTransactionalGuard.shouldAutoStop(goalText: "Make a reservation for me", inspection: inspection) == false)
        #expect(BrowserTransactionalGuard.approvalShouldBeRequired(
            actionName: "click_selector",
            detail: "Complete reservation",
            transactionalKind: "final_confirmation",
            inspection: inspection
        ) == false)
    }

    @Test
    func browserPageAnalyzerInfersMissingPhoneRequirement() throws {
        let inspectionWithPhone = ChromiumInspection(
            title: "Checkout details",
            url: "https://example.com/checkout",
            pageStage: "form",
            formCount: 1,
            hasSearchField: false,
            interactiveElements: [],
            forms: [
                ChromiumSemanticForm(
                    id: "contact-form",
                    label: "Contact details",
                    selector: "form.contact",
                    submitLabel: "Continue",
                    fields: [
                        ChromiumSemanticFormField(
                            id: "field-phone",
                            label: "Phone number",
                            selector: "input[name=\"phone\"]",
                            controlType: "tel",
                            value: nil,
                            options: [],
                            autocomplete: "tel",
                            inputMode: "tel",
                            fieldPurpose: "phone_number",
                            isRequired: true,
                            isSelected: false,
                            validationMessage: "Phone number is required."
                        )
                    ]
                )
            ],
            resultLists: [],
            cards: [],
            dialogs: [],
            controlGroups: [],
            autocompleteSurfaces: [],
            datePickers: [],
            notices: [],
            stepIndicators: [],
            primaryActions: [],
            transactionalBoundaries: [],
            semanticTargets: [],
            booking: nil,
            bookingFunnel: nil
        )

        let requirements = BrowserPageAnalyzer.requirements(for: inspectionWithPhone)
        let workflow = try #require(BrowserPageAnalyzer.workflow(for: inspectionWithPhone))

        #expect(requirements.first?.kind == "phone_number")
        #expect(workflow.stage == "details_form")
        #expect(workflow.readyToContinue == false)
    }

    @Test
    func browserPageAnalyzerInfersFinalSubmitWhenRequirementsAreSatisfied() throws {
        let inspection = ChromiumInspection(
            title: "Complete reservation",
            url: "https://example.com/review",
            pageStage: "final_confirmation",
            formCount: 0,
            hasSearchField: false,
            interactiveElements: [],
            forms: [],
            resultLists: [],
            cards: [],
            dialogs: [],
            controlGroups: [],
            autocompleteSurfaces: [],
            datePickers: [],
            notices: [],
            stepIndicators: [],
            primaryActions: [
                ChromiumSemanticAction(
                    id: "action-final",
                    label: "Complete reservation",
                    selector: "#complete-reservation",
                    role: "button",
                    priority: 100
                )
            ],
            transactionalBoundaries: [
                ChromiumTransactionalBoundary(
                    id: "boundary-final",
                    kind: "final_confirmation",
                    label: "Complete reservation",
                    selector: "#complete-reservation",
                    confidence: 98
                )
            ],
            semanticTargets: [],
            booking: nil,
            bookingFunnel: nil
        )

        let workflow = try #require(BrowserPageAnalyzer.workflow(for: inspection))

        #expect(workflow.stage == "final_submit")
        #expect(workflow.readyToContinue)
        #expect(workflow.finalBoundaryLabel == "Complete reservation")
    }

    @Test
    func browserPageAnalyzerInfersVerificationFromStepIndicatorsAndNotices() throws {
        let inspection = ChromiumInspection(
            title: "Verify your code",
            url: "https://example.com/verify",
            pageStage: "form",
            formCount: 0,
            hasSearchField: false,
            interactiveElements: [],
            forms: [],
            resultLists: [],
            cards: [],
            dialogs: [],
            controlGroups: [],
            autocompleteSurfaces: [],
            datePickers: [],
            notices: [
                ChromiumSemanticNotice(
                    id: "notice-0",
                    kind: "info",
                    label: "Enter the 6-digit verification code we texted you",
                    selector: ".verification-message"
                )
            ],
            stepIndicators: [
                ChromiumStepIndicator(
                    id: "step-0",
                    label: "Verify phone",
                    selector: ".step.verify",
                    isCurrent: true
                )
            ],
            primaryActions: [],
            transactionalBoundaries: [],
            semanticTargets: [],
            booking: nil,
            bookingFunnel: nil
        )

        let workflow = try #require(BrowserPageAnalyzer.workflow(for: inspection))
        #expect(workflow.stage == "verification")
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
    bookingFunnel: ChromiumBookingFunnelState? = nil,
    semanticTargets: [ChromiumSemanticTarget]? = nil,
    booking: ChromiumBookingSemanticState? = nil
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
                isRequired: true,
                isSelected: false,
                validationMessage: nil,
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
                        autocomplete: nil,
                        inputMode: nil,
                        fieldPurpose: "location",
                        isRequired: true,
                        isSelected: false,
                        validationMessage: nil
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
        notices: [],
        stepIndicators: [],
        primaryActions: [],
        transactionalBoundaries: boundaries,
        semanticTargets: semanticTargets ?? [
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
        booking: booking,
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
