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
        let strippedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (strippedText, nil)
        }

        if let extracted = strictExtraction(from: text, using: regex) ?? bestEffortExtraction(from: text) {
            let payload = extracted.payload
            let stripped = extracted.displayText
            guard let data = payload.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(BrowserAgentCommand.self, from: data) else {
                return (stripped, nil)
            }
            return (stripped, decoded)
        }

        return (strippedText, nil)
    }

    private static func strictExtraction(
        from text: String,
        using regex: NSRegularExpression
    ) -> (payload: String, displayText: String)? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let commandRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text) else {
            return nil
        }

        let payload = String(text[commandRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = text.replacingCharacters(in: fullRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (payload, stripped)
    }

    private static func bestEffortExtraction(from text: String) -> (payload: String, displayText: String)? {
        let startTag = "<agenthub_browser_command>"
        guard let startRange = text.range(of: startTag) else {
            return nil
        }

        let suffix = text[startRange.upperBound...]
        guard let jsonRange = firstJSONObjectRange(in: suffix) else {
            let stripped = text[..<startRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return ("", String(stripped))
        }

        let payload = String(suffix[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let afterJSONIndex = jsonRange.upperBound
        let trailing = suffix[afterJSONIndex...]
        let removalEnd = trailing.range(of: "</agenthub_browser_command>")?.upperBound ?? afterJSONIndex
        let fullRange = startRange.lowerBound..<removalEnd
        let stripped = stripCommandMarkers(in: text.replacingCharacters(in: fullRange, with: ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (payload, stripped)
    }

    private static func firstJSONObjectRange(in text: Substring) -> Range<Substring.Index>? {
        var objectStart: Substring.Index?
        var depth = 0
        var isEscaped = false
        var isInsideString = false

        for index in text.indices {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{":
                if objectStart == nil {
                    objectStart = index
                }
                depth += 1
            case "}":
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let objectStart {
                    return objectStart..<text.index(after: index)
                }
            default:
                continue
            }
        }

        return nil
    }

    private static func stripCommandMarkers(in text: String) -> String {
        text
            .replacingOccurrences(of: "<agenthub_browser_command>", with: "")
            .replacingOccurrences(of: "</agenthub_browser_command>", with: "")
            .replacingOccurrences(of: "</agenthub_browser_command", with: "")
            .replacingOccurrences(of: "<agenthub_browser_command", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
