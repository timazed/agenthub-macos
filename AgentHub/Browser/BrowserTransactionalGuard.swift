import Foundation

enum BrowserTransactionalGuard {
    nonisolated static func shouldAutoStop(goalText: String, inspection: ChromiumInspection?) -> Bool {
        guard let inspection else { return false }
        guard isTransactionalGoal(goalText) else { return false }
        guard let boundary = highConfidenceFinalBoundary(in: inspection) else { return false }
        return stageAllowsAutoStop(for: inspection, boundary: boundary)
    }

    nonisolated static func stopReason(goalText: String, inspection: ChromiumInspection?) -> String? {
        guard shouldAutoStop(goalText: goalText, inspection: inspection) else { return nil }
        if let boundary = inspection.flatMap(highConfidenceFinalBoundary(in:)) {
            let label = boundary.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                return "Stopped before the final confirmation boundary at \"\(label)\"."
            }
        }
        return "Stopped before the final confirmation boundary."
    }

    nonisolated static func approvalShouldBeRequired(
        actionName: String,
        detail: String,
        transactionalKind: String?,
        inspection: ChromiumInspection?
    ) -> Bool {
        if transactionalKind == "final_confirmation" {
            guard let inspection else { return true }
            return stageAllowsApprovalGate(for: inspection, detail: detail)
        }
        let haystack = "\(actionName) \(detail)".lowercased()
        guard finalConfirmationKeywords.contains(where: { haystack.contains($0) }) else {
            return false
        }
        guard let inspection else { return true }
        return stageAllowsApprovalGate(for: inspection, detail: detail)
    }

    nonisolated static func highConfidenceFinalBoundary(in inspection: ChromiumInspection) -> ChromiumTransactionalBoundary? {
        inspection.transactionalBoundaries
            .filter {
                $0.kind == "final_confirmation"
                    && !isPromotionalOrDiscoveryLabel($0.label)
                    && !isNonTransactionalSavedItemAction($0.label)
                    && !isDiscoveryNavigationLabel($0.label)
                    && !isAccountChoiceLabel($0.label)
                    && ($0.confidence >= 85 || isFinalConfirmationLabel($0.label))
            }
            .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
            .first
    }

    nonisolated private static func stageAllowsAutoStop(
        for inspection: ChromiumInspection,
        boundary: ChromiumTransactionalBoundary
    ) -> Bool {
        guard let workflow = BrowserPageAnalyzer.workflow(for: inspection) else { return false }
        if workflow.hasSuccessSignal || workflow.hasFailureSignal {
            return false
        }
        guard workflow.requirements.isEmpty else { return false }

        switch workflow.stage {
        case "final_submit":
            return true
        case "review":
            return isStrongerThanSlotSelectionLabel(boundary.label)
        case "verification", "details_form", "selection", "discovery", "browse", "dialog":
            return false
        default:
            return false
        }
    }

    nonisolated private static func stageAllowsApprovalGate(
        for inspection: ChromiumInspection,
        detail: String
    ) -> Bool {
        guard let workflow = BrowserPageAnalyzer.workflow(for: inspection) else { return true }
        if workflow.hasSuccessSignal || workflow.hasFailureSignal {
            return false
        }
        guard workflow.requirements.isEmpty else { return false }

        switch workflow.stage {
        case "final_submit":
            return true
        case "review":
            return isStrongerThanSlotSelectionLabel(detail)
        case "verification", "details_form", "selection", "discovery", "browse", "dialog":
            return false
        default:
            return false
        }
    }

    nonisolated private static func isTransactionalGoal(_ goalText: String) -> Bool {
        let lowered = goalText.lowercased()
        return transactionalGoalKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static func isFinalConfirmationLabel(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return finalConfirmationKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static func isPromotionalOrDiscoveryLabel(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return promotionalOrDiscoveryKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static func isNonTransactionalSavedItemAction(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return savedItemKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static func isDiscoveryNavigationLabel(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return discoveryNavigationKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static func isAccountChoiceLabel(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return accountChoiceKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static func isStrongerThanSlotSelectionLabel(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return strongerLateStageKeywords.contains { lowered.contains($0) }
    }

    nonisolated private static let transactionalGoalKeywords = [
        "book",
        "booking",
        "reservation",
        "reserve",
        "checkout",
        "purchase",
        "buy",
        "place order",
        "hotel",
        "flight"
    ]

    nonisolated private static let finalConfirmationKeywords = [
        "reserve",
        "purchase",
        "pay",
        "confirm",
        "confirm reservation",
        "complete booking",
        "complete reservation",
        "place order",
        "book now",
        "finalize"
    ]

    nonisolated private static let promotionalOrDiscoveryKeywords = [
        "explore restaurants",
        "exclusive tables",
        "new cardmembers",
        "dining credit",
        "sapphire reserve",
        "learn more",
        "see details"
    ]

    nonisolated private static let savedItemKeywords = [
        "save restaurant",
        "save to favorites",
        "save restaurant to favorites",
        "favorite",
        "favourite",
        "favorites",
        "favourites",
        "saved items",
        "wishlist",
        "bookmark"
    ]

    nonisolated private static let discoveryNavigationKeywords = [
        "view full list",
        "view all",
        "see all",
        "show all",
        "browse all",
        "explore all",
        "view more"
    ]

    nonisolated private static let accountChoiceKeywords = [
        "use email instead",
        "continue with email",
        "continue with phone",
        "phone number",
        "verify your account",
        "verify account",
        "sign in",
        "log in",
        "login"
    ]

    nonisolated private static let strongerLateStageKeywords = [
        "confirm",
        "confirm reservation",
        "complete booking",
        "complete reservation",
        "place order",
        "finalize",
        "pay",
        "purchase"
    ]
}
