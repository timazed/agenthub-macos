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

enum BrowserPageAnalyzer {
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
        let reviewLike = inspection.pageStage == "review"
            || inspection.dialogs.contains { $0.label.localizedCaseInsensitiveContains("review") }
            || inspection.stepIndicators.contains { $0.label.localizedCaseInsensitiveContains("review") || $0.label.localizedCaseInsensitiveContains("details") }
            || inspection.forms.contains { form in
                let haystack = [form.label, form.submitLabel ?? ""].joined(separator: " ").lowercased()
                return haystack.contains("review") || haystack.contains("summary")
            }
            || inspection.transactionalBoundaries.contains { $0.kind == "review_step" }
            || inspection.bookingFunnel?.hasReviewSummary == true
        let verificationLike = requirements.contains(where: { $0.kind == "verification_code" })
            || inspection.notices.contains { notice in
                let label = notice.label.lowercased()
                return label.contains("verification") || label.contains("code") || label.contains("passcode")
            }
            || inspection.stepIndicators.contains { $0.label.localizedCaseInsensitiveContains("verify") }
        let slotSelection = inspection.semanticTargets.contains { $0.kind == "slot_option" }
            || inspection.bookingFunnel?.hasSlotSelection == true
        let selectionStage = inspection.pageStage == "results"
            || !inspection.resultLists.isEmpty
            || inspection.cards.count >= 2
            || slotSelection
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
        } else if verificationLike {
            stage = "verification"
        } else if finalBoundary != nil && requirements.isEmpty {
            if let legacyWorkflowHint, ["discovery", "selection"].contains(legacyWorkflowHint) {
                stage = legacyWorkflowHint
            } else {
                stage = "final_submit"
            }
        } else if let legacyWorkflowHint, ["discovery", "selection", "details_form", "review"].contains(legacyWorkflowHint) {
            stage = legacyWorkflowHint
        } else if finalBoundary != nil || reviewLike {
            stage = "review"
        } else if hasDataEntryForm || requirements.contains(where: { $0.kind != "verification_code" }) {
            stage = "details_form"
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

    nonisolated private static func pageSignals(for inspection: ChromiumInspection) -> (hasSuccess: Bool, hasFailure: Bool) {
        let rawSignals = [
            inspection.title,
            inspection.url,
            inspection.pageStage,
            inspection.dialogs.map(\.label).joined(separator: "\n"),
            inspection.forms.map(\.label).joined(separator: "\n"),
            inspection.notices.map(\.label).joined(separator: "\n"),
            inspection.stepIndicators.map(\.label).joined(separator: "\n"),
            inspection.transactionalBoundaries.map(\.label).joined(separator: "\n"),
            inspection.transactionalBoundaries.map(\.kind).joined(separator: "\n"),
            inspection.primaryActions.map(\.label).joined(separator: "\n")
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
                    || signal.contains("reservation complete")
                    || signal.contains("booking confirmed")
                    || signal.contains("order placed")
                    || signal.contains("thank you")
            }
            || inspection.notices.contains(where: { $0.kind == "success" })
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
