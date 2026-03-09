import Foundation

enum BrowserTransactionalGuard {
    nonisolated static func shouldAutoStop(goalText: String, inspection: ChromiumInspection?) -> Bool {
        guard let inspection else { return false }
        guard isTransactionalGoal(goalText) else { return false }

        if inspection.pageStage == "final_confirmation" {
            return true
        }

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
}
