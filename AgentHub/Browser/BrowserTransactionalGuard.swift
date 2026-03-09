import Foundation

enum BrowserTransactionalGuard {
    nonisolated static func shouldAutoStop(goalText: String, inspection: ChromiumInspection?) -> Bool {
        guard let inspection else { return false }
        guard isTransactionalGoal(goalText) else { return false }

        return highConfidenceFinalBoundary(in: inspection) != nil
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

    nonisolated static func approvalShouldBeRequired(actionName: String, detail: String, transactionalKind: String?) -> Bool {
        if transactionalKind == "final_confirmation" {
            return true
        }
        let haystack = "\(actionName) \(detail)".lowercased()
        return finalConfirmationKeywords.contains { haystack.contains($0) }
    }

    nonisolated static func highConfidenceFinalBoundary(in inspection: ChromiumInspection) -> ChromiumTransactionalBoundary? {
        inspection.transactionalBoundaries
            .filter {
                $0.kind == "final_confirmation"
                    && !isPromotionalOrDiscoveryLabel($0.label)
                    && !isNonTransactionalSavedItemAction($0.label)
                    && !isDiscoveryNavigationLabel($0.label)
                    && ($0.confidence >= 85 || isFinalConfirmationLabel($0.label))
            }
            .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
            .first
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
        "complete booking",
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
}
