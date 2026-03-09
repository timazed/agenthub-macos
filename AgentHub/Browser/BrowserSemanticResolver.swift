import Foundation

struct BrowserSemanticResolution: Equatable {
    let selector: String?
    let label: String?
    let transactionalKind: String?
    let target: ChromiumSemanticTarget?
}

enum BrowserSemanticResolver {
    nonisolated static func resolve(_ command: BrowserAgentCommand, inspection: ChromiumInspection?) -> BrowserSemanticResolution {
        guard let inspection else {
            return BrowserSemanticResolution(
                selector: command.selector,
                label: command.label,
                transactionalKind: nil,
                target: nil
            )
        }

        switch command.action {
        case .typeText, .selectOption:
            if let target = bestFieldTarget(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: target.selector,
                    label: command.label ?? target.label,
                    transactionalKind: target.transactionalKind,
                    target: target
                )
            }
        case .chooseAutocompleteOption:
            if let target = bestAutocompleteTarget(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: target.selector,
                    label: command.label ?? target.label,
                    transactionalKind: nil,
                    target: target
                )
            }
        case .chooseGroupedOption:
            if let target = bestGroupOptionTarget(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: target.selector,
                    label: command.label ?? target.groupLabel ?? target.label,
                    transactionalKind: nil,
                    target: target
                )
            }
        case .pickDate:
            if let target = bestDateTarget(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: target.selector,
                    label: command.label ?? target.label,
                    transactionalKind: nil,
                    target: target
                )
            }
        case .submitForm:
            if let form = bestForm(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: form.selector,
                    label: command.label ?? form.label,
                    transactionalKind: form.submitLabel.map(transactionalKind(for:)) ?? mostRelevantBoundary(in: inspection)?.kind,
                    target: nil
                )
            }
        case .clickSelector:
            if let target = bestActionTarget(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: target.selector,
                    label: command.label ?? target.label,
                    transactionalKind: target.transactionalKind,
                    target: target
                )
            }
        case .clickText:
            if let target = bestActionTarget(for: command, inspection: inspection) {
                return BrowserSemanticResolution(
                    selector: target.selector,
                    label: command.label ?? target.label,
                    transactionalKind: target.transactionalKind,
                    target: target
                )
            }
        default:
            break
        }

        return BrowserSemanticResolution(
            selector: command.selector,
            label: command.label,
            transactionalKind: nil,
            target: nil
        )
    }

    nonisolated static func bestEffortRetarget(
        _ command: BrowserAgentCommand,
        staleInspection: ChromiumInspection?,
        refreshedInspection: ChromiumInspection
    ) -> BrowserSemanticResolution? {
        let previous = resolve(command, inspection: staleInspection)
        let refreshed = resolve(command, inspection: refreshedInspection)
        guard refreshed.selector != nil else { return nil }
        if resolutionsDiffer(refreshed, previous) {
            return refreshed
        }
        if command.selector == nil, refreshed.selector != nil {
            return refreshed
        }
        return nil
    }

    nonisolated private static func bestFieldTarget(for command: BrowserAgentCommand, inspection: ChromiumInspection) -> ChromiumSemanticTarget? {
        bestTarget(
            in: inspection.semanticTargets,
            matching: command.label,
            fallbackText: nil,
            preferredKinds: ["field", "autocomplete", "date_picker"],
            preferredPurposes: ["location", "search", "guest_count", "date"],
            selectorHint: command.selector
        )
    }

    nonisolated private static func bestAutocompleteTarget(for command: BrowserAgentCommand, inspection: ChromiumInspection) -> ChromiumSemanticTarget? {
        bestTarget(
            in: inspection.semanticTargets,
            matching: command.label,
            fallbackText: command.text,
            preferredKinds: ["autocomplete", "field"],
            preferredPurposes: ["location", "search", "guest_count"],
            selectorHint: command.selector
        )
    }

    nonisolated private static func bestGroupOptionTarget(for command: BrowserAgentCommand, inspection: ChromiumInspection) -> ChromiumSemanticTarget? {
        let desiredOption = normalize(command.text)
        var bestTarget: ChromiumSemanticTarget?
        var bestScore = Int.min
        for target in inspection.semanticTargets where target.kind == "group_option" {
            var score = scoreTarget(target, matching: command.label, fallbackText: command.text, selectorHint: command.selector)
            if normalize(target.label) == desiredOption {
                score += 120
            } else if !desiredOption.isEmpty, normalize(target.label).contains(desiredOption) {
                score += 90
            }
            if let groupLabel = target.groupLabel, fuzzyContains(groupLabel, command.label) {
                score += 50
            }
            guard score > 0 else { continue }
            if score > bestScore || (score == bestScore && target.priority > (bestTarget?.priority ?? Int.min)) {
                bestTarget = target
                bestScore = score
            }
        }
        return bestTarget
    }

    nonisolated private static func bestDateTarget(for command: BrowserAgentCommand, inspection: ChromiumInspection) -> ChromiumSemanticTarget? {
        bestTarget(
            in: inspection.semanticTargets,
            matching: command.label,
            fallbackText: command.text,
            preferredKinds: ["date_picker", "field"],
            preferredPurposes: ["date"],
            selectorHint: command.selector
        )
    }

    nonisolated private static func bestActionTarget(for command: BrowserAgentCommand, inspection: ChromiumInspection) -> ChromiumSemanticTarget? {
        bestTarget(
            in: inspection.semanticTargets,
            matching: command.label,
            fallbackText: command.text,
            preferredKinds: ["slot_option", "dialog_action", "primary_action", "result_card", "action", "dialog_dismiss"],
            preferredPurposes: ["time", "continue", "confirm", "dismiss"],
            selectorHint: command.selector
        )
    }

    nonisolated private static func bestForm(for command: BrowserAgentCommand, inspection: ChromiumInspection) -> ChromiumSemanticForm? {
        let desiredLabel = normalize(command.label)
        var bestForm: ChromiumSemanticForm?
        var bestScore = Int.min
        for form in inspection.forms {
            var score = 0
            if let selector = command.selector, selector == form.selector {
                score += 200
            }
            if !desiredLabel.isEmpty {
                let label = normalize(form.label)
                if label == desiredLabel {
                    score += 140
                } else if label.contains(desiredLabel) || desiredLabel.contains(label) {
                    score += 90
                }
                let fieldHaystack = form.fields.map(\.label).joined(separator: " ")
                if fuzzyContains(fieldHaystack, command.label) {
                    score += 55
                }
            }
            if let submitLabel = form.submitLabel {
                score += transactionalKind(for: submitLabel) == "final_confirmation" ? 15 : 30
            }
            guard score > 0 || command.selector == nil else { continue }
            if score > bestScore {
                bestForm = form
                bestScore = score
            }
        }
        return bestForm
    }

    nonisolated private static func bestTarget(
        in targets: [ChromiumSemanticTarget],
        matching preferredLabel: String?,
        fallbackText: String?,
        preferredKinds: [String],
        preferredPurposes: [String],
        selectorHint: String?
    ) -> ChromiumSemanticTarget? {
        let kindSet = Set(preferredKinds)
        let purposeSet = Set(preferredPurposes)
        var bestTarget: ChromiumSemanticTarget?
        var bestScore = Int.min
        for target in targets {
            var score = scoreTarget(target, matching: preferredLabel, fallbackText: fallbackText, selectorHint: selectorHint)
            if kindSet.contains(target.kind) {
                score += 45
            }
            if let purpose = target.purpose, purposeSet.contains(purpose) {
                score += 35
            }
            guard score > 0 || selectorHint == nil else { continue }
            if score > bestScore || (score == bestScore && target.priority > (bestTarget?.priority ?? Int.min)) {
                bestTarget = target
                bestScore = score
            }
        }
        return bestTarget
    }

    nonisolated private static func scoreTarget(
        _ target: ChromiumSemanticTarget,
        matching preferredLabel: String?,
        fallbackText: String?,
        selectorHint: String?
    ) -> Int {
        var score = target.priority
        let normalizedLabel = normalize(target.label)
        let normalizedGroup = normalize(target.groupLabel)

        if let selectorHint, !selectorHint.isEmpty {
            if target.selector == selectorHint { score += 250 }
            else if target.selector.contains(selectorHint) || selectorHint.contains(target.selector) { score += 90 }
        }

        if let preferredLabel, !preferredLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let desired = normalize(preferredLabel)
            if normalizedLabel == desired || normalizedGroup == desired { score += 160 }
            else if normalizedLabel.contains(desired) || desired.contains(normalizedLabel) { score += 110 }
            else if normalizedGroup.contains(desired) || desired.contains(normalizedGroup) { score += 80 }
        }

        if let fallbackText, !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let desired = normalize(fallbackText)
            if normalizedLabel == desired { score += 120 }
            else if normalizedLabel.contains(desired) { score += 85 }
        }

        if target.transactionalKind == "final_confirmation" { score += 20 }
        if target.transactionalKind == "booking_slot" { score += 30 }
        if isAuthChoiceLabel(target.label) { score -= 160 }
        if isSkipOrUtilityLabel(target.label) { score -= 180 }
        return score
    }

    nonisolated private static func mostRelevantBoundary(in inspection: ChromiumInspection) -> ChromiumTransactionalBoundary? {
        inspection.transactionalBoundaries
            .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
            .first
    }

    nonisolated private static func transactionalKind(for label: String) -> String? {
        let normalized = label.lowercased()
        if normalized.contains("reserve")
            || normalized.contains("confirm")
            || normalized.contains("complete")
            || normalized.contains("purchase")
            || normalized.contains("pay") {
            return "final_confirmation"
        }
        if normalized.contains("checkout") || normalized.contains("review") || normalized.contains("continue") || normalized.contains("next") {
            return "review_step"
        }
        if normalized.contains("search") || normalized.contains("find") || normalized.contains("show results") {
            return "search_submit"
        }
        return nil
    }

    nonisolated private static func fuzzyContains(_ haystack: String?, _ needle: String?) -> Bool {
        let normalizedHaystack = normalize(haystack)
        let normalizedNeedle = normalize(needle)
        guard !normalizedHaystack.isEmpty, !normalizedNeedle.isEmpty else { return false }
        return normalizedHaystack.contains(normalizedNeedle) || normalizedNeedle.contains(normalizedHaystack)
    }

    nonisolated private static func resolutionsDiffer(
        _ lhs: BrowserSemanticResolution,
        _ rhs: BrowserSemanticResolution
    ) -> Bool {
        lhs.selector != rhs.selector
            || lhs.label != rhs.label
            || lhs.transactionalKind != rhs.transactionalKind
            || lhs.target?.id != rhs.target?.id
    }

    nonisolated private static func normalize(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isAuthChoiceLabel(_ value: String?) -> Bool {
        let normalized = normalize(value)
        return normalized.contains("use email instead")
            || normalized.contains("continue with email")
            || normalized.contains("continue with phone")
            || normalized.contains("use phone instead")
            || normalized.contains("sign in")
            || normalized.contains("log in")
            || normalized.contains("login")
    }

    nonisolated private static func isSkipOrUtilityLabel(_ value: String?) -> Bool {
        let normalized = normalize(value)
        return normalized.contains("skip to main content")
            || normalized.contains("skip navigation")
            || normalized.contains("skip to content")
            || normalized.contains("map")
            || normalized.contains("directions")
            || normalized.contains("share")
            || normalized.contains("save")
            || normalized.contains("favorite")
            || normalized.contains("favourite")
            || normalized.contains("bookmark")
    }
}
