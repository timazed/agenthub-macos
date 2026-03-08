import Foundation

enum BrowserAgentAction: String, Codable {
    case inspectPage = "inspect_page"
    case openURL = "open_url"
    case clickSelector = "click_selector"
    case clickText = "click_text"
    case typeText = "type_text"
    case selectOption = "select_option"
    case chooseAutocompleteOption = "choose_autocomplete_option"
    case chooseGroupedOption = "choose_grouped_option"
    case pickDate = "pick_date"
    case submitForm = "submit_form"
    case pressKey = "press_key"
    case scroll = "scroll"
    case waitForText = "wait_for_text"
    case waitForSelector = "wait_for_selector"
    case waitForNavigation = "wait_for_navigation"
    case waitForResults = "wait_for_results"
    case waitForDialog = "wait_for_dialog"
    case waitForSettle = "wait_for_settle"
    case captureSnapshot = "capture_snapshot"
    case done
}

struct BrowserAgentCommand: Codable, Equatable {
    var action: BrowserAgentAction
    var url: String?
    var selector: String?
    var text: String?
    var key: String?
    var timeoutSeconds: Double?
    var deltaY: Double?
    var label: String?
    var finalResponse: String?
    var rationale: String?
}

struct BrowserAgentExecutionResult: Equatable {
    let summary: String
    let inspection: ChromiumInspection?
}

enum BrowserAgentResponseParser {
    static func parse(_ text: String) -> (displayText: String, command: BrowserAgentCommand?) {
        let pattern = #"<agenthub_browser_command>([\s\S]*?)</agenthub_browser_command>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let commandRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let payload = String(text[commandRange])
        let stripped = text.replacingCharacters(in: fullRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(BrowserAgentCommand.self, from: data) else {
            return (stripped, nil)
        }
        return (stripped, decoded)
    }
}
