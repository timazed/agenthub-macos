import Foundation

enum BrowserScenarioClassifier {
    nonisolated static func category(forGoalText goalText: String, initialURL: String?) -> String {
        let goal = goalText.lowercased()
        let url = (initialURL ?? "").lowercased()

        if goal.contains("opentable") || url.contains("opentable") || goal.contains("restaurant") {
            return "restaurant"
        }
        if goal.contains("booking.com")
            || url.contains("booking.com")
            || goal.contains("expedia")
            || url.contains("expedia")
            || goal.contains("hotel") {
            return "hotel"
        }
        if goal.contains("google flights")
            || url.contains("google.com/travel/flights")
            || goal.contains("kayak")
            || url.contains("kayak")
            || goal.contains("flight") {
            return "flight"
        }
        if goal.contains("amazon")
            || url.contains("amazon")
            || goal.contains("checkout")
            || goal.contains("place order")
            || goal.contains("purchase") {
            return "checkout"
        }
        return "other"
    }
}
