import Foundation

struct BrowserPageRequirement: Equatable, Identifiable {
    let id: String
    let kind: String
    let label: String
    let selector: String?
    let controlType: String
    let fillAction: String
    let options: [String]
    let prompt: String
    let isSensitive: Bool
    let priority: Int
    let validationMessage: String?
}

struct BrowserWorkflowSnapshot: Equatable {
    let stage: String
    let requirements: [BrowserPageRequirement]
    let hasFinalConfirmationBoundary: Bool
    let finalBoundaryLabel: String?
    let hasSuccessSignal: Bool
    let hasFailureSignal: Bool
    let readyToContinue: Bool
}

enum BrowserCanonicalStage: String, Equatable {
    case discovery
    case results
    case detail
    case detailsForm = "details_form"
    case approvalBoundary = "approval_boundary"
    case review
    case phoneVerificationPrep = "phone_verification_prep"
    case verificationCode = "verification_code"
    case success
    case failure
    case dialog
    case browse
}

struct BrowserCanonicalState: Equatable {
    let stage: BrowserCanonicalStage
    let workflow: BrowserWorkflowSnapshot
    let promptableRequirement: BrowserPageRequirement?
    let approvalBoundaryLabel: String?
    let requiresVisualRefresh: Bool
}

enum BrowserPageAnalyzer {
    nonisolated static func canonicalState(
        for inspection: ChromiumInspection?,
        priorInspection: ChromiumInspection? = nil
    ) -> BrowserCanonicalState? {
        guard let inspection,
              let workflow = workflow(for: inspection) else {
            return nil
        }

        let promptableRequirement = workflow.requirements.first(where: { $0.kind != "consent" }) ?? workflow.requirements.first
        let approvalBoundaryLabel = BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection)?.label
        let approvedFinalRequirement = followUpRequirementAfterApprovedFinalAction(
            currentInspection: inspection,
            priorInspection: priorInspection
        )
        let synthesizedVerificationRequirement = BrowserPageRequirement(
            id: "synthetic-canonical-verification",
            kind: "verification_code",
            label: "Verification code",
            selector: nil,
            controlType: "one-time-code",
            fillAction: "type_text",
            options: [],
            prompt: promptForRequirementKind("verification_code", label: "Verification code"),
            isSensitive: true,
            priority: requirementPriority("verification_code"),
            validationMessage: "The current page is waiting on a verification step."
        )
        let verificationOrPhoneKinds: Set<String> = ["phone_number", "verification_code", "consent"]
        let onlyVerificationPrepRequirements = !workflow.requirements.isEmpty
            && workflow.requirements.allSatisfy { verificationOrPhoneKinds.contains($0.kind) }
        let hasLateStageVerificationBoundary = BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection) != nil
            && (
                ["review", "final_submit"].contains(workflow.stage)
                    || inspection.bookingFunnel?.hasReviewSummary == true
                    || inspection.bookingFunnel?.hasFinalConfirmationBoundary == true
            )

        let stage: BrowserCanonicalStage
        let canonicalPromptableRequirement: BrowserPageRequirement?

        if workflow.hasSuccessSignal {
            stage = .success
            canonicalPromptableRequirement = nil
        } else if workflow.hasFailureSignal {
            stage = .failure
            canonicalPromptableRequirement = nil
        } else if let approvedFinalRequirement {
            canonicalPromptableRequirement = approvedFinalRequirement
            stage = approvedFinalRequirement.kind == "phone_number" ? .phoneVerificationPrep : .verificationCode
        } else if let promptableRequirement,
                  promptableRequirement.kind == "phone_number",
                  hasLateStageVerificationBoundary,
                  onlyVerificationPrepRequirements {
            canonicalPromptableRequirement = promptableRequirement
            stage = .phoneVerificationPrep
        } else if promptableRequirement?.kind == "verification_code" || verificationInterruptionLikely(for: inspection) {
            canonicalPromptableRequirement = promptableRequirement ?? synthesizedVerificationRequirement
            stage = .verificationCode
        } else if workflow.stage == "details_form" {
            canonicalPromptableRequirement = promptableRequirement
            stage = .detailsForm
        } else if workflow.stage == "final_submit" {
            canonicalPromptableRequirement = nil
            stage = .approvalBoundary
        } else if workflow.stage == "review" {
            canonicalPromptableRequirement = promptableRequirement
            stage = .review
        } else if workflow.stage == "selection" {
            canonicalPromptableRequirement = promptableRequirement
            stage = canonicalSelectionStage(for: inspection)
        } else if workflow.stage == "discovery" {
            canonicalPromptableRequirement = promptableRequirement
            stage = .discovery
        } else if workflow.stage == "dialog" {
            canonicalPromptableRequirement = promptableRequirement
            stage = .dialog
        } else {
            canonicalPromptableRequirement = promptableRequirement
            stage = .browse
        }

        let requiresVisualRefresh = [.phoneVerificationPrep, .verificationCode].contains(stage)

        return BrowserCanonicalState(
            stage: stage,
            workflow: workflow,
            promptableRequirement: canonicalPromptableRequirement,
            approvalBoundaryLabel: approvalBoundaryLabel,
            requiresVisualRefresh: requiresVisualRefresh
        )
    }

    nonisolated static func userFacingProgressMessage(for state: BrowserCanonicalState) -> String? {
        switch state.stage {
        case .discovery:
            return "I’m still navigating the site to reach the requested flow."
        case .results:
            return "I’m on the results step and narrowing to the exact venue."
        case .detail:
            return "I’m on the venue detail step and still working through the booking flow."
        case .review:
            return "I’m on the review step and still working through the booking flow."
        case .success:
            return "The browser flow reached a success state."
        case .failure:
            return "The browser flow is currently blocked by a failure state."
        case .dialog:
            return "The browser flow is paused on a dialog and still needs a decision or next step."
        case .browse:
            return "I’m still working through the browser flow."
        case .detailsForm, .approvalBoundary, .phoneVerificationPrep, .verificationCode:
            return nil
        }
    }

    nonisolated static func augmentInspection(
        _ inspection: ChromiumInspection,
        withVisualRecognitionText recognizedText: String,
        fallback: ChromiumInspection?
    ) -> ChromiumInspection {
        let normalized = recognizedText.lowercased()
        let phoneVerificationGate = normalized.contains("phone number is required")
            || (
                normalized.contains("phone number")
                    && (normalized.contains("text message") || normalized.contains("verify your account"))
            )
        let verificationGate = normalized.contains("enter verification code")
            || normalized.contains("verification code")
            || normalized.contains("didn't receive the code")
            || normalized.contains("didnt receive the code")

        guard phoneVerificationGate || verificationGate else {
            return inspection
        }

        var interactiveElements = inspection.interactiveElements
        var notices = inspection.notices
        var stepIndicators = inspection.stepIndicators
        var dialogs = inspection.dialogs

        let phoneSelector = requiredFieldSelector(kind: "phone_number", in: inspection)
            ?? requiredFieldSelector(kind: "phone_number", in: fallback)
            ?? (inspection.url.contains("opentable.com/booking/details") ? "#phoneNumber" : nil)

        if phoneVerificationGate,
           !requirements(for: inspection).contains(where: { $0.kind == "phone_number" }),
           let phoneSelector {
            interactiveElements.append(
                ChromiumInteractiveElement(
                    id: "visual-phone-number",
                    role: "textbox",
                    label: "Phone number",
                    text: "",
                    selector: phoneSelector,
                    value: nil,
                    href: nil,
                    purpose: "phone_number",
                    groupLabel: "Verification",
                    isRequired: true,
                    isSelected: false,
                    validationMessage: normalized.contains("phone number is required") ? "Phone number is required." : nil,
                    priority: 160
                )
            )
        }

        if phoneVerificationGate,
           !notices.contains(where: { $0.label.localizedCaseInsensitiveContains("text message") }) {
            notices.append(
                ChromiumSemanticNotice(
                    id: "visual-phone-verification-notice",
                    kind: "status",
                    label: "You will receive a text message to verify your account.",
                    selector: ".agenthub-visual-phone-verification"
                )
            )
        }

        if verificationGate,
           !notices.contains(where: { $0.label.localizedCaseInsensitiveContains("verification code") }) {
            notices.append(
                ChromiumSemanticNotice(
                    id: "visual-verification-code-notice",
                    kind: "status",
                    label: "Enter verification code to reserve.",
                    selector: ".agenthub-visual-verification-code"
                )
            )
        }

        if verificationGate,
           !stepIndicators.contains(where: { $0.label.localizedCaseInsensitiveContains("verify") }) {
            stepIndicators.append(
                ChromiumStepIndicator(
                    id: "visual-verify-step",
                    label: "Verify phone",
                    selector: ".agenthub-visual-verify-step",
                    isCurrent: true
                )
            )
        }

        if verificationGate,
           dialogs.isEmpty {
            dialogs.append(
                ChromiumSemanticDialog(
                    id: "visual-verification-dialog",
                    label: "Enter verification code to reserve",
                    selector: ".agenthub-visual-verification-dialog",
                    primaryActionLabel: nil,
                    primaryActionSelector: nil,
                    dismissSelector: nil
                )
            )
        }

        return ChromiumInspection(
            title: inspection.title,
            url: inspection.url,
            pageStage: inspection.pageStage,
            formCount: inspection.formCount,
            hasSearchField: inspection.hasSearchField,
            interactiveElements: interactiveElements,
            forms: inspection.forms,
            resultLists: inspection.resultLists,
            cards: inspection.cards,
            dialogs: dialogs,
            controlGroups: inspection.controlGroups,
            autocompleteSurfaces: inspection.autocompleteSurfaces,
            datePickers: inspection.datePickers,
            notices: notices,
            stepIndicators: stepIndicators,
            primaryActions: inspection.primaryActions,
            transactionalBoundaries: inspection.transactionalBoundaries,
            semanticTargets: inspection.semanticTargets,
            booking: inspection.booking,
            bookingFunnel: inspection.bookingFunnel
        )
    }

    nonisolated static func requirements(for inspection: ChromiumInspection?) -> [BrowserPageRequirement] {
        guard let inspection else { return [] }

        var requirements: [BrowserPageRequirement] = []
        var seenRequirementKeys = Set<String>()

        func insertRequirement(
            id: String,
            kind: String,
            label: String,
            selector: String?,
            controlType: String,
            fillAction: String,
            options: [String],
            prompt: String,
            isSensitive: Bool,
            priority: Int,
            validationMessage: String?
        ) {
            let key = [kind, selector ?? "", label.lowercased()].joined(separator: "|")
            guard !seenRequirementKeys.contains(key) else { return }
            seenRequirementKeys.insert(key)
            requirements.append(
                BrowserPageRequirement(
                    id: id,
                    kind: kind,
                    label: label,
                    selector: selector,
                    controlType: controlType,
                    fillAction: fillAction,
                    options: options,
                    prompt: prompt,
                    isSensitive: isSensitive,
                    priority: priority,
                    validationMessage: validationMessage
                )
            )
        }

        for form in inspection.forms {
            for field in form.fields {
                guard fieldNeedsInput(field) else { continue }
                let kind = classifyFieldKind(
                    label: field.label,
                    controlType: field.controlType,
                    autocomplete: field.autocomplete,
                    inputMode: field.inputMode,
                    purpose: field.fieldPurpose,
                    selector: field.selector
                )
                let prompt = promptForRequirementKind(kind, label: field.label)
                let fillAction = fillActionForField(field, kind: kind)
                insertRequirement(
                    id: field.id,
                    kind: kind,
                    label: field.label,
                    selector: field.selector,
                    controlType: field.controlType,
                    fillAction: fillAction,
                    options: field.options,
                    prompt: prompt,
                    isSensitive: isSensitiveRequirement(kind),
                    priority: requirementPriority(kind),
                    validationMessage: field.validationMessage
                )
            }
        }

        for element in inspection.interactiveElements {
            guard interactiveElementNeedsInput(element) else { continue }
            let kind = classifyFieldKind(
                label: element.label,
                controlType: element.role,
                autocomplete: nil,
                inputMode: nil,
                purpose: element.purpose,
                selector: element.selector
            )
            let prompt = promptForRequirementKind(kind, label: element.label)
            insertRequirement(
                id: element.id,
                kind: kind,
                label: element.label,
                selector: element.selector,
                controlType: element.role,
                fillAction: kind == "consent" ? "click" : "type_text",
                options: [],
                prompt: prompt,
                isSensitive: isSensitiveRequirement(kind),
                priority: requirementPriority(kind),
                validationMessage: element.validationMessage
            )
        }

        if !requirements.contains(where: { $0.kind == "verification_code" }),
           verificationInterruptionLikely(for: inspection) {
            insertRequirement(
                id: "synthetic-verification-interruption",
                kind: "verification_code",
                label: "Verification code",
                selector: nil,
                controlType: "one-time-code",
                fillAction: "type_text",
                options: [],
                prompt: promptForRequirementKind("verification_code", label: "Verification code"),
                isSensitive: true,
                priority: requirementPriority("verification_code") + 5,
                validationMessage: "The current page is waiting on a verification step."
            )
        }

        return requirements.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.priority > rhs.priority
        }
    }

    nonisolated static func workflow(for inspection: ChromiumInspection?) -> BrowserWorkflowSnapshot? {
        guard let inspection else { return nil }

        let rawRequirements = requirements(for: inspection)
        let finalBoundary = BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection)
        let signals = pageSignals(for: inspection)
        let legacyWorkflowHint = legacyWorkflowStage(for: inspection.bookingFunnel?.stage)
        let hasLateStageSignals = finalBoundary != nil
            || inspection.pageStage == "review"
            || inspection.pageStage == "final_confirmation"
            || inspection.bookingFunnel?.hasReviewSummary == true
            || inspection.bookingFunnel?.hasGuestDetailsForm == true
            || inspection.bookingFunnel?.hasPaymentForm == true
        let requirements = hasLateStageSignals
            ? rawRequirements.filter { !["search", "location", "date", "time", "guest_count"].contains($0.kind) }
            : rawRequirements
        let hasPromptableNonVerificationRequirements = requirements.contains {
            $0.kind != "verification_code" && $0.kind != "consent"
        }
        let reviewLike = inspection.pageStage == "review"
            || inspection.dialogs.contains { $0.label.localizedCaseInsensitiveContains("review") }
            || inspection.stepIndicators.contains { $0.label.localizedCaseInsensitiveContains("review") || $0.label.localizedCaseInsensitiveContains("details") }
            || inspection.forms.contains { form in
                let haystack = [form.label, form.submitLabel ?? ""].joined(separator: " ").lowercased()
                return haystack.contains("review") || haystack.contains("summary")
            }
            || inspection.transactionalBoundaries.contains { $0.kind == "review_step" }
            || inspection.bookingFunnel?.hasReviewSummary == true
        let hasNonVerificationRequirements = requirements.contains { $0.kind != "verification_code" }
        let verificationLike = !hasPromptableNonVerificationRequirements && (
            requirements.contains(where: { $0.kind == "verification_code" })
            || explicitVerificationSurfacePresent(in: inspection)
            || (!hasNonVerificationRequirements && inspection.notices.contains { notice in
                let label = notice.label.lowercased()
                return label.contains("verification") || label.contains("code") || label.contains("passcode")
            })
            || (!hasNonVerificationRequirements && inspection.stepIndicators.contains { $0.label.localizedCaseInsensitiveContains("verify") })
        )
        let slotSelection = inspection.semanticTargets.contains { $0.kind == "slot_option" }
            || inspection.bookingFunnel?.hasSlotSelection == true
        let selectionStage = (inspection.pageStage == "results"
            || !inspection.resultLists.isEmpty
            || inspection.cards.count >= 2
            || slotSelection)
            && !hasLateStageSignals
        let discoveryStage = inspection.hasSearchField
            || inspection.pageStage == "search"
            || inspection.primaryActions.contains { action in
                let label = action.label.lowercased()
                return label.contains("search") || label.contains("find")
            }
        let hasDataEntryForm = inspection.forms.contains { form in
            form.fields.contains { field in
                let kind = classifyFieldKind(
                    label: field.label,
                    controlType: field.controlType,
                    autocomplete: field.autocomplete,
                    inputMode: field.inputMode,
                    purpose: field.fieldPurpose,
                    selector: field.selector
                )
                return !["search", "location", "date", "time", "guest_count"].contains(kind)
            }
        }

        let stage: String
        if signals.hasSuccess {
            stage = "success"
        } else if signals.hasFailure {
            stage = "failure"
        } else if hasPromptableNonVerificationRequirements && (finalBoundary != nil || reviewLike || hasDataEntryForm || detailsCollectionInterruptionLikely(for: inspection)) {
            stage = "details_form"
        } else if verificationLike {
            stage = "verification"
        } else if !requirements.isEmpty && (finalBoundary != nil || reviewLike) {
            stage = "details_form"
        } else if finalBoundary != nil && requirements.isEmpty {
            stage = "final_submit"
        } else if finalBoundary != nil || reviewLike {
            stage = "review"
        } else if let legacyWorkflowHint, ["details_form", "review"].contains(legacyWorkflowHint) {
            stage = legacyWorkflowHint
        } else if hasDataEntryForm || requirements.contains(where: { $0.kind != "verification_code" }) {
            stage = "details_form"
        } else if let legacyWorkflowHint, ["discovery", "selection"].contains(legacyWorkflowHint) {
            stage = legacyWorkflowHint
        } else if selectionStage {
            stage = "selection"
        } else if discoveryStage {
            stage = "discovery"
        } else if !inspection.dialogs.isEmpty {
            stage = "dialog"
        } else {
            stage = "browse"
        }

        let readyToContinue = requirements.isEmpty && !signals.hasSuccess && !signals.hasFailure

        return BrowserWorkflowSnapshot(
            stage: stage,
            requirements: requirements,
            hasFinalConfirmationBoundary: finalBoundary != nil,
            finalBoundaryLabel: finalBoundary?.label,
            hasSuccessSignal: signals.hasSuccess,
            hasFailureSignal: signals.hasFailure,
            readyToContinue: readyToContinue
        )
    }

    nonisolated private static func legacyWorkflowStage(for bookingStage: String?) -> String? {
        switch bookingStage {
        case "search":
            return "discovery"
        case "results", "venue_detail", "booking_widget", "slot_selection":
            return "selection"
        case "guest_details":
            return "details_form"
        case "review":
            return "review"
        case "final_confirmation":
            return "final_submit"
        default:
            return nil
        }
    }

    nonisolated private static func canonicalSelectionStage(for inspection: ChromiumInspection) -> BrowserCanonicalStage {
        if inspection.pageStage == "results"
            || inspection.bookingFunnel?.stage == "results"
            || !inspection.resultLists.isEmpty
            || inspection.cards.count >= 2 {
            return .results
        }
        if inspection.pageStage == "detail"
            || inspection.pageStage == "venue_detail"
            || inspection.bookingFunnel?.stage == "venue_detail"
            || inspection.bookingFunnel?.stage == "booking_widget"
            || inspection.bookingFunnel?.stage == "slot_selection" {
            return .detail
        }
        return .detail
    }

    nonisolated private static func requiredFieldSelector(kind: String, in inspection: ChromiumInspection?) -> String? {
        requirements(for: inspection)
            .filter { $0.kind == kind }
            .sorted { $0.priority > $1.priority }
            .first?
            .selector
    }

    nonisolated private static func classifyFieldKind(
        label: String,
        controlType: String,
        autocomplete: String?,
        inputMode: String?,
        purpose: String?,
        selector: String
    ) -> String {
        let descriptor = [label, controlType, autocomplete ?? "", inputMode ?? "", purpose ?? "", selector]
            .joined(separator: " ")
            .lowercased()
        if descriptor.contains("verification") || descriptor.contains("one-time-code") || descriptor.contains("otp") || descriptor.contains("passcode") || descriptor.contains("auth code") {
            return "verification_code"
        }
        if descriptor.contains("phone") || descriptor.contains("mobile") || descriptor.contains("contact number") || descriptor.contains(" tel") || descriptor.contains("phone_number") {
            return "phone_number"
        }
        if descriptor.contains("email") || descriptor.contains("e-mail") {
            return "email"
        }
        if descriptor.contains("first name") || descriptor.contains("given name") || descriptor.contains("first_name") {
            return "first_name"
        }
        if descriptor.contains("last name") || descriptor.contains("surname") || descriptor.contains("family name") || descriptor.contains("last_name") {
            return "last_name"
        }
        if descriptor.contains("full name") || descriptor.contains("your name") || descriptor.contains("guest name") || descriptor.contains("traveler name") || descriptor.contains("passenger name") || descriptor.contains("full_name") {
            return "full_name"
        }
        if descriptor.contains("address line 1") || descriptor.contains("street address") || descriptor.contains("billing address") || descriptor.contains("shipping address") || descriptor.contains("address_line1") {
            return "address_line1"
        }
        if descriptor.contains("address line 2") || descriptor.contains("suite") || descriptor.contains("apt") || descriptor.contains("unit") || descriptor.contains("address_line2") {
            return "address_line2"
        }
        if descriptor.contains("postal") || descriptor.contains("zip") || descriptor.contains("postal_code") {
            return "postal_code"
        }
        if descriptor.contains("state") || descriptor.contains("province") || descriptor.contains("region") {
            return "state"
        }
        if descriptor.contains("country") {
            return "country"
        }
        if descriptor.contains("city") || descriptor.contains("town") {
            return "city"
        }
        if descriptor.contains("terms") || descriptor.contains("conditions") || descriptor.contains("agree") || descriptor.contains("consent") || descriptor.contains("newsletter") || descriptor.contains("marketing") || descriptor.contains("reminders") {
            return "consent"
        }
        if descriptor.contains("card number") || descriptor.contains("credit card") || descriptor.contains("debit card") || descriptor.contains("payment_card_number") {
            return "payment_card_number"
        }
        if descriptor.contains("cvv") || descriptor.contains("cvc") || descriptor.contains("payment_security_code") {
            return "payment_security_code"
        }
        if descriptor.contains("exp") || descriptor.contains("expiry") || descriptor.contains("expiration") || descriptor.contains("payment_expiry") {
            return "payment_expiry"
        }
        if descriptor.contains("date") || descriptor.contains("calendar") || descriptor.contains("check-in") || descriptor.contains("arrival") || descriptor.contains("departure") {
            return "date"
        }
        if descriptor.contains("time") || descriptor.contains("seating") {
            return "time"
        }
        if descriptor.contains("guest") || descriptor.contains("party") || descriptor.contains("traveler") || descriptor.contains("traveller") || descriptor.contains("passenger") || descriptor.contains("room") {
            return "guest_count"
        }
        if descriptor.contains("search") || descriptor.contains("find") {
            return "search"
        }
        if descriptor.contains("destination") || descriptor.contains("location") || descriptor.contains("airport") {
            return "location"
        }
        return "required_field"
    }

    nonisolated private static func fieldNeedsInput(_ field: ChromiumSemanticFormField) -> Bool {
        if field.controlType.lowercased().contains("checkbox") || field.controlType.lowercased().contains("radio") {
            return field.isRequired && !field.isSelected
        }
        let value = normalizedValue(field.value)
        if field.isRequired && value.isEmpty {
            return true
        }
        if let validationMessage = field.validationMessage, !validationMessage.isEmpty, value.isEmpty {
            return true
        }
        return false
    }

    nonisolated private static func interactiveElementNeedsInput(_ element: ChromiumInteractiveElement) -> Bool {
        guard element.isRequired || !(element.validationMessage?.isEmpty ?? true) else {
            return false
        }
        let role = element.role.lowercased()
        if role.contains("checkbox") || role.contains("radio") {
            return !element.isSelected
        }
        let value = normalizedValue(element.value)
        return value.isEmpty
    }

    nonisolated private static func normalizedValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        let lowered = trimmed.lowercased()
        if ["select", "choose", "select an option", "select a value", "phone number", "email", "name", "address"].contains(lowered) {
            return ""
        }
        return trimmed
    }

    nonisolated private static func fillActionForField(_ field: ChromiumSemanticFormField, kind: String) -> String {
        let controlType = field.controlType.lowercased()
        if controlType.contains("checkbox") || controlType.contains("radio") || kind == "consent" {
            return "click"
        }
        if controlType.contains("select") || controlType.contains("listbox") {
            return "select_option"
        }
        return "type_text"
    }

    nonisolated private static func promptForRequirementKind(_ kind: String, label: String) -> String {
        switch kind {
        case "phone_number":
            return "I still need your phone number."
        case "email":
            return "I still need your email address."
        case "full_name":
            return "I still need your full name."
        case "first_name":
            return "I still need your first name."
        case "last_name":
            return "I still need your last name."
        case "address_line1":
            return "I still need your street address."
        case "address_line2":
            return "I still need your apartment or unit details."
        case "city":
            return "I still need your city."
        case "state":
            return "I still need your state or province."
        case "postal_code":
            return "I still need your postal code."
        case "country":
            return "I still need your country."
        case "verification_code":
            return "I still need the verification code for this page."
        case "consent":
            return "I still need your approval for the required consent option."
        case "payment_card_number":
            return "I still need your payment card number."
        case "payment_expiry":
            return "I still need your card expiry."
        case "payment_security_code":
            return "I still need your card security code."
        case "date":
            return "I still need the date for this step."
        case "time":
            return "I still need the time for this step."
        case "guest_count":
            return "I still need the guest or traveler count."
        default:
            return "I still need the required field \"\(label)\"."
        }
    }

    nonisolated private static func isSensitiveRequirement(_ kind: String) -> Bool {
        ["phone_number", "email", "full_name", "first_name", "last_name", "address_line1", "address_line2", "city", "state", "postal_code", "country", "verification_code", "payment_card_number", "payment_expiry", "payment_security_code"].contains(kind)
    }

    nonisolated private static func requirementPriority(_ kind: String) -> Int {
        switch kind {
        case "verification_code": return 140
        case "payment_card_number", "payment_expiry", "payment_security_code": return 130
        case "phone_number", "email", "full_name", "first_name", "last_name": return 120
        case "address_line1", "address_line2", "city", "state", "postal_code", "country": return 110
        case "consent": return 90
        case "date", "time", "guest_count": return 80
        default: return 60
        }
    }

    nonisolated static func verificationInterruptionLikely(for inspection: ChromiumInspection) -> Bool {
        let hasDirectContactRequirement = inspection.forms.contains { form in
            form.fields.contains { field in
                guard fieldNeedsInput(field) else { return false }
                let kind = classifyFieldKind(
                    label: field.label,
                    controlType: field.controlType,
                    autocomplete: field.autocomplete,
                    inputMode: field.inputMode,
                    purpose: field.fieldPurpose,
                    selector: field.selector
                )
                return kind != "verification_code"
            }
        } || inspection.interactiveElements.contains { element in
            guard interactiveElementNeedsInput(element) else { return false }
            let kind = classifyFieldKind(
                label: element.label,
                controlType: element.role,
                autocomplete: nil,
                inputMode: nil,
                purpose: element.purpose,
                selector: element.selector
            )
            return kind != "verification_code"
        }

        if hasDirectContactRequirement && detailsCollectionInterruptionLikely(for: inspection) {
            return false
        }

        let combined = [
            inspection.title,
            inspection.url,
            inspection.pageStage,
            inspection.dialogs.map(\.label).joined(separator: "\n"),
            inspection.forms.map(\.label).joined(separator: "\n"),
            inspection.forms.flatMap(\.fields).map(\.label).joined(separator: "\n"),
            inspection.interactiveElements.map(\.label).joined(separator: "\n"),
            inspection.notices.map(\.label).joined(separator: "\n"),
            inspection.stepIndicators.map(\.label).joined(separator: "\n"),
            inspection.primaryActions.map(\.label).joined(separator: "\n"),
            inspection.transactionalBoundaries.map(\.label).joined(separator: "\n"),
            inspection.semanticTargets.map(\.label).joined(separator: "\n")
        ]
        .joined(separator: "\n")
        .lowercased()

        let verificationSignals = [
            "verification code",
            "enter code",
            "one-time code",
            "one time code",
            "passcode",
            "otp",
            "verify phone",
            "verify your phone",
            "verify account",
            "verify your account",
            "text message",
            "we texted you",
            "sent a code",
            "sent you a code"
        ]
        if verificationSignals.contains(where: combined.contains), !hasDirectContactRequirement {
            return true
        }

        let authInterruptionSignals = [
            "sign in",
            "log in",
            "login",
            "use email instead",
            "use phone instead",
            "continue with email",
            "continue with phone"
        ]
        let hasAuthInterruption = authInterruptionSignals.contains(where: combined.contains)
        let hasModalInterruption = !inspection.dialogs.isEmpty || inspection.pageStage == "dialog"
        let lateStageContext = combined.contains("complete reservation")
            || combined.contains("booking/details")
            || combined.contains("reservation details")
            || combined.contains("review")
            || inspection.bookingFunnel?.hasReviewSummary == true
            || inspection.bookingFunnel?.hasFinalConfirmationBoundary == true
        let hasExplicitVerificationContext = verificationSignals.contains(where: combined.contains)
            || inspection.notices.contains { notice in
                let label = notice.label.lowercased()
                return label.contains("verification")
                    || label.contains("code")
                    || label.contains("passcode")
                    || label.contains("we texted")
                    || label.contains("sent a code")
            }
            || inspection.stepIndicators.contains { indicator in
                let label = indicator.label.lowercased()
                return label.contains("verify")
                    || label.contains("verification")
                    || label.contains("code")
            }
            || explicitVerificationSurfacePresent(in: inspection)

        return hasAuthInterruption
            && hasModalInterruption
            && lateStageContext
            && hasExplicitVerificationContext
            && !hasDirectContactRequirement
    }

    nonisolated static func finalBoundaryMayTriggerVerification(for inspection: ChromiumInspection?) -> Bool {
        guard let inspection else { return false }
        guard BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection) != nil else {
            return false
        }
        guard !verificationInterruptionLikely(for: inspection) else {
            return false
        }
        guard let workflow = workflow(for: inspection),
              ["review", "final_submit"].contains(workflow.stage),
              workflow.requirements.isEmpty,
              workflow.hasSuccessSignal == false,
              workflow.hasFailureSignal == false else {
            return false
        }
        guard !detailsCollectionInterruptionLikely(for: inspection) || workflow.requirements.isEmpty else {
            return false
        }

        let combined = [
            inspection.title,
            inspection.url,
            inspection.pageStage,
            inspection.dialogs.map(\.label).joined(separator: "\n"),
            inspection.forms.map(\.label).joined(separator: "\n"),
            inspection.forms.flatMap(\.fields).map { "\($0.label) \($0.value ?? "")" }.joined(separator: "\n"),
            inspection.interactiveElements.map { "\($0.label) \($0.value ?? "")" }.joined(separator: "\n"),
            inspection.notices.map(\.label).joined(separator: "\n"),
            inspection.stepIndicators.map(\.label).joined(separator: "\n"),
            inspection.primaryActions.map(\.label).joined(separator: "\n"),
            inspection.transactionalBoundaries.map(\.label).joined(separator: "\n"),
            inspection.semanticTargets.map(\.label).joined(separator: "\n")
        ]
        .joined(separator: "\n")
        .lowercased()

        let authChoiceSignals = [
            "use email instead",
            "use phone instead",
            "continue with email",
            "continue with phone",
            "sign in",
            "log in",
            "login"
        ]
        let verificationDeliverySignals = [
            "text message",
            "we'll send a text",
            "we will send a text",
            "sent a text",
            "verify your account",
            "verify account",
            "verify your phone",
            "verify phone"
        ]
        let hasPhoneContext = inspection.forms.contains { form in
            form.fields.contains { field in
                classifyFieldKind(
                    label: field.label,
                    controlType: field.controlType,
                    autocomplete: field.autocomplete,
                    inputMode: field.inputMode,
                    purpose: field.fieldPurpose,
                    selector: field.selector
                ) == "phone_number"
            }
        } || inspection.interactiveElements.contains { element in
            classifyFieldKind(
                label: element.label,
                controlType: element.role,
                autocomplete: nil,
                inputMode: nil,
                purpose: element.purpose,
                selector: element.selector
            ) == "phone_number"
        } || combined.contains("phone number")

        return hasPhoneContext
            && authChoiceSignals.contains(where: combined.contains)
            && (
                verificationDeliverySignals.contains(where: combined.contains)
                    || combined.contains("booking/details")
                    || combined.contains("complete reservation")
            )
    }

    nonisolated static func followUpRequirementAfterApprovedFinalAction(
        currentInspection: ChromiumInspection?,
        priorInspection: ChromiumInspection?
    ) -> BrowserPageRequirement? {
        guard let currentInspection, let priorInspection else { return nil }
        let explicitVerificationSurface = explicitVerificationSurfacePresent(in: currentInspection)
        guard explicitVerificationSurface || finalBoundaryMayTriggerVerification(for: priorInspection) else {
            return nil
        }

        let currentWorkflow = workflow(for: currentInspection)
        guard currentWorkflow?.hasSuccessSignal == false,
              currentWorkflow?.hasFailureSignal == false else {
            return nil
        }

        let currentRequirements = requirements(for: currentInspection)
        let promptableRequirements = currentRequirements.filter { $0.kind != "consent" }
        let allowedRequirementKinds: Set<String> = ["phone_number", "verification_code"]
        guard promptableRequirements.allSatisfy({ allowedRequirementKinds.contains($0.kind) }) else {
            return nil
        }

        let verificationRequirement = promptableRequirements.first(where: { $0.kind == "verification_code" })
        let phoneRequirement = promptableRequirements.first(where: { $0.kind == "phone_number" })

        if explicitVerificationSurface {
            if let verificationRequirement {
                return verificationRequirement
            }
            return BrowserPageRequirement(
                id: "synthetic-approved-final-verification-surface",
                kind: "verification_code",
                label: "Verification code",
                selector: nil,
                controlType: "one-time-code",
                fillAction: "type_text",
                options: [],
                prompt: promptForRequirementKind("verification_code", label: "Verification code"),
                isSensitive: true,
                priority: requirementPriority("verification_code") + 10,
                validationMessage: "The current page is showing a verification code prompt."
            )
        }

        if verificationInterruptionLikely(for: currentInspection) {
            if let phoneRequirement {
                return phoneRequirement
            }
            if let verificationRequirement {
                return verificationRequirement
            }
        }

        guard !currentRequirements.contains(where: { $0.kind != "verification_code" && $0.kind != "consent" && $0.kind != "phone_number" }) else {
            return nil
        }

        let currentCombined = [
            currentInspection.title,
            currentInspection.url,
            currentInspection.pageStage,
            currentInspection.dialogs.map(\.label).joined(separator: "\n"),
            currentInspection.forms.map(\.label).joined(separator: "\n"),
            currentInspection.forms.flatMap(\.fields).map { "\($0.label) \($0.value ?? "")" }.joined(separator: "\n"),
            currentInspection.interactiveElements.map { "\($0.label) \($0.value ?? "")" }.joined(separator: "\n"),
            currentInspection.notices.map(\.label).joined(separator: "\n"),
            currentInspection.stepIndicators.map(\.label).joined(separator: "\n"),
            currentInspection.primaryActions.map(\.label).joined(separator: "\n"),
            currentInspection.transactionalBoundaries.map(\.label).joined(separator: "\n")
        ]
        .joined(separator: "\n")
        .lowercased()

        let stillInLateStageBooking = currentCombined.contains("booking/details")
            || currentCombined.contains("complete reservation")
            || currentInspection.bookingFunnel?.hasReviewSummary == true
            || currentInspection.bookingFunnel?.hasFinalConfirmationBoundary == true
            || currentInspection.pageStage == "review"
            || currentInspection.pageStage == "final_confirmation"
        guard stillInLateStageBooking else {
            return nil
        }

        let authChoiceSignals = [
            "use email instead",
            "use phone instead",
            "continue with email",
            "continue with phone",
            "sign in",
            "log in",
            "login"
        ]
        let hasPhoneContext = currentInspection.forms.contains { form in
            form.fields.contains { field in
                classifyFieldKind(
                    label: field.label,
                    controlType: field.controlType,
                    autocomplete: field.autocomplete,
                    inputMode: field.inputMode,
                    purpose: field.fieldPurpose,
                    selector: field.selector
                ) == "phone_number"
            }
        } || currentInspection.interactiveElements.contains { element in
            classifyFieldKind(
                label: element.label,
                controlType: element.role,
                autocomplete: nil,
                inputMode: nil,
                purpose: element.purpose,
                selector: element.selector
            ) == "phone_number"
        } || currentCombined.contains("phone number")

        if let phoneRequirement {
            return phoneRequirement
        }
        if let verificationRequirement {
            return verificationRequirement
        }
        guard hasPhoneContext || authChoiceSignals.contains(where: currentCombined.contains) else {
            return nil
        }
        return BrowserPageRequirement(
            id: "synthetic-approved-final-verification",
            kind: "verification_code",
            label: "Verification code",
            selector: nil,
            controlType: "one-time-code",
            fillAction: "type_text",
            options: [],
            prompt: promptForRequirementKind("verification_code", label: "Verification code"),
            isSensitive: true,
            priority: requirementPriority("verification_code") + 5,
            validationMessage: "The current page is waiting on a verification step."
        )
    }

    nonisolated static func verificationLikelyAfterApprovedFinalAction(
        currentInspection: ChromiumInspection?,
        priorInspection: ChromiumInspection?
    ) -> Bool {
        followUpRequirementAfterApprovedFinalAction(
            currentInspection: currentInspection,
            priorInspection: priorInspection
        ) != nil
    }

    nonisolated static func shouldPreserveVerificationContext(
        currentInspection: ChromiumInspection?,
        pendingInspection: ChromiumInspection?
    ) -> Bool {
        if let currentInspection, verificationInterruptionLikely(for: currentInspection) {
            return true
        }

        guard let pendingInspection,
              canonicalState(for: pendingInspection)?.requiresVisualRefresh == true else {
            return false
        }

        guard let currentInspection else {
            return true
        }

        if let currentState = canonicalState(for: currentInspection, priorInspection: pendingInspection) {
            switch currentState.stage {
            case .phoneVerificationPrep, .verificationCode:
                return true
            case .success, .failure, .detailsForm:
                return false
            default:
                break
            }
        }

        let combined = [
            currentInspection.title,
            currentInspection.url,
            currentInspection.pageStage,
            currentInspection.dialogs.map(\.label).joined(separator: "\n"),
            currentInspection.forms.map(\.label).joined(separator: "\n"),
            currentInspection.forms.flatMap(\.fields).map(\.label).joined(separator: "\n"),
            currentInspection.notices.map(\.label).joined(separator: "\n"),
            currentInspection.stepIndicators.map(\.label).joined(separator: "\n"),
            currentInspection.transactionalBoundaries.map(\.label).joined(separator: "\n")
        ]
        .joined(separator: "\n")
        .lowercased()

        let sameBookingDocument = currentInspection.url == pendingInspection.url
            || (
                currentInspection.url.contains("opentable.com/booking/details")
                    && pendingInspection.url.contains("opentable.com/booking/details")
            )

        let lateStageBooking = sameBookingDocument
            && (
                currentInspection.pageStage == "review"
                    || currentInspection.pageStage == "final_confirmation"
                    || currentInspection.bookingFunnel?.hasReviewSummary == true
                    || currentInspection.bookingFunnel?.hasFinalConfirmationBoundary == true
                    || combined.contains("complete reservation")
                    || combined.contains("reservation details")
            )

        return lateStageBooking
    }

    nonisolated private static func explicitVerificationSurfacePresent(in inspection: ChromiumInspection) -> Bool {
        let dialogSignals = inspection.dialogs.contains { dialog in
            let label = dialog.label.lowercased()
            return label.contains("verification code")
                || label.contains("enter code")
                || label.contains("one-time code")
                || label.contains("otp")
                || label.contains("passcode")
        }
        let formSignals = inspection.forms.contains { form in
            let combined = [form.label, form.submitLabel ?? ""].joined(separator: " ").lowercased()
            return combined.contains("verification code")
                || combined.contains("enter code")
                || combined.contains("one-time code")
                || combined.contains("otp")
                || combined.contains("passcode")
                || form.fields.contains { field in
                    let kind = classifyFieldKind(
                        label: field.label,
                        controlType: field.controlType,
                        autocomplete: field.autocomplete,
                        inputMode: field.inputMode,
                        purpose: field.fieldPurpose,
                        selector: field.selector
                    )
                    return kind == "verification_code"
                }
        }
        return dialogSignals || formSignals
    }

    nonisolated private static func detailsCollectionInterruptionLikely(for inspection: ChromiumInspection) -> Bool {
        let detailsLabels = inspection.dialogs.contains { dialog in
            let label = dialog.label.lowercased()
            return label.contains("add some details")
                || label.contains("last step")
                || label.contains("complete your details")
                || label.contains("guest details")
        } || inspection.forms.contains { form in
            let combined = [form.label, form.submitLabel ?? ""].joined(separator: " ").lowercased()
            return combined.contains("add some details")
                || combined.contains("last step")
                || combined.contains("guest details")
                || combined.contains("diner details")
        }

        let requiredIdentityFieldPresent = inspection.forms.contains { form in
            form.fields.contains { field in
                guard fieldNeedsInput(field) else { return false }
                let kind = classifyFieldKind(
                    label: field.label,
                    controlType: field.controlType,
                    autocomplete: field.autocomplete,
                    inputMode: field.inputMode,
                    purpose: field.fieldPurpose,
                    selector: field.selector
                )
                return ["first_name", "last_name", "full_name", "email", "phone_number"].contains(kind)
            }
        }

        return detailsLabels || requiredIdentityFieldPresent
    }

    nonisolated private static func pageSignals(for inspection: ChromiumInspection) -> (hasSuccess: Bool, hasFailure: Bool) {
        let rawSignals = [
            inspection.title,
            inspection.url,
            inspection.pageStage,
            inspection.dialogs.map(\.label).joined(separator: "\n"),
            inspection.forms.map(\.label).joined(separator: "\n"),
            inspection.notices.map(\.label).joined(separator: "\n"),
            inspection.stepIndicators.map(\.label).joined(separator: "\n")
        ]
        let signals = rawSignals
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasSuccess = signals.contains { signal in
                signal.contains("confirmed")
                    || signal.contains("reservation confirmed")
                    || signal.contains("booking confirmation")
                    || signal.contains("order confirmation")
                    || signal.contains("confirmation number")
                    || signal.contains("booking confirmed")
                    || signal.contains("order placed")
                    || signal.contains("thank you")
            }
            || inspection.notices.contains(where: { notice in
                notice.kind == "success"
                    && !notice.label.lowercased().contains("complete reservation")
                    && !notice.label.lowercased().contains("complete your reservation")
            })
        let hasFailure = signals.contains { signal in
                signal.contains("expired")
                    || signal.contains("timed out")
                    || signal.contains("session timeout")
                    || signal.contains("session expired")
                    || signal.contains("no longer available")
                    || signal.contains("invalid code")
                    || signal.contains("incorrect code")
                    || signal.contains("try again")
                    || signal.contains("couldn t complete")
                    || signal.contains("could not complete")
            }
            || inspection.notices.contains(where: { notice in
                let label = notice.label.lowercased()
                return notice.kind == "error"
                    && (label.contains("expired")
                        || label.contains("timed out")
                        || label.contains("session expired")
                        || label.contains("invalid code")
                        || label.contains("incorrect code")
                        || label.contains("try again")
                        || label.contains("no longer available"))
            })
            || inspection.forms.flatMap(\.fields).contains { field in
                let message = field.validationMessage?.lowercased() ?? ""
                return message.contains("invalid")
                    || message.contains("incorrect")
                    || message.contains("expired")
                    || message.contains("try again")
            }
        return (hasSuccess, hasFailure)
    }
}
