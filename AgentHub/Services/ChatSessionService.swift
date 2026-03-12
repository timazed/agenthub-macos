import Foundation

enum ChatSessionEvent {
    case assistantDelta(String)
    case assistantMessage(String)
    case stderr(String)
    case proposal(TaskProposal)
    case completed
    case failed(String)
}

protocol ChatSessionServicing {
    func loadMessages() throws -> [Message]
    func streamEvents() -> AsyncStream<ChatSessionEvent>
    func sendUserMessage(_ text: String) async throws
    func cancelCurrentRun() throws
}

struct ChatBrowserIntent: Equatable {
    enum Kind: Equatable {
        case openTableRestaurantSearch
    }

    let kind: Kind
    let request: ChromiumRestaurantSearchRequest
    let bookingRequested: Bool
    let bookingParameters: ChromiumRestaurantBookingParameters
    let providedData: BrowserSessionFollowUpData?

    var genericBrowserIntent: GenericBrowserChatIntent {
        GenericBrowserChatIntent(
            goalText: genericGoalText,
            initialURL: request.siteURL,
            goalFocusTerms: [request.venueName, request.locationHint].compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            },
            providedData: providedData
        )
    }

    private var genericGoalText: String {
        if bookingRequested {
            var components: [String] = [
                "Use the browser to first open the exact venue page for \(request.venueName)"
            ]
            if let locationHint = request.locationHint, !locationHint.isEmpty {
                components[0] += " in \(locationHint)"
            }
            components.append("on OpenTable")
            if let dateText = bookingParameters.dateText, !dateText.isEmpty {
                components.append("for \(dateText)")
            }
            if let timeText = bookingParameters.timeText, !timeText.isEmpty {
                components.append("at \(timeText)")
            }
            if let partySize = bookingParameters.partySize {
                components.append("for \(partySize) people")
            }
            components.append("Only after reaching the exact venue page, set the reservation details there")
            components.append("choose the closest available reservation slot if the exact time is unavailable")
            components.append("and stop before the final reservation confirmation step")
            return components.joined(separator: " ")
        }

        var text = "Use the browser to find \(request.venueName)"
        if let locationHint = request.locationHint, !locationHint.isEmpty {
            text += " in \(locationHint)"
        }
        text += " on OpenTable and open the venue page"
        return text
    }

    nonisolated static func parse(_ text: String) -> ChatBrowserIntent? {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()
        guard lowered.contains("opentable") || lowered.contains("open table") else {
            return nil
        }

        let bookingRequested = ["reservation", "reserve", "book", "booking"].contains { lowered.contains($0) }
        let segments = normalized
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let venueAndLocation = extractVenueAndLocation(from: segments, fullText: normalized)
        guard let venueName = venueAndLocation.venueName, !venueName.isEmpty else {
            return nil
        }

        let locationHint = venueAndLocation.locationHint
        let query = [venueName, locationHint]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")

        return ChatBrowserIntent(
            kind: .openTableRestaurantSearch,
            request: ChromiumRestaurantSearchRequest(
                siteURL: "https://www.opentable.com",
                query: query,
                venueName: venueName,
                locationHint: locationHint
            ),
            bookingRequested: bookingRequested,
            bookingParameters: extractBookingParameters(from: lowered),
            providedData: BrowserSessionFollowUpParser.parse(text)
        )
    }

    private nonisolated static func extractBookingParameters(from loweredText: String) -> ChromiumRestaurantBookingParameters {
        let partySize = firstMatch(
            in: loweredText,
            patterns: [
                #"party of (\d+)"#,
                #"for (\d+) people"#,
                #"(\d+) people"#
            ]
        ).flatMap(Int.init)

        let timeText = firstMatch(
            in: loweredText,
            patterns: [
                #"\b(\d{1,2}(?::\d{2})?\s?(?:am|pm))\b"#,
                #"\bat (\d{1,2}(?::\d{2})?\s?(?:am|pm))\b"#
            ]
        )

        let dateText = firstMatch(
            in: loweredText,
            patterns: [
                #"\b(today|tomorrow)\b"#,
                #"\b((?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?)\b"#
            ]
        )

        return ChromiumRestaurantBookingParameters(
            dateText: dateText,
            timeText: timeText,
            partySize: partySize
        )
    }

    private nonisolated static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let captureRange = Range(match.range(at: captureIndex), in: text) else { continue }
            let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private nonisolated static func extractVenueAndLocation(from segments: [String], fullText: String) -> (venueName: String?, locationHint: String?) {
        var cleanedSegments = segments
            .map(cleanSegment)
            .filter { !$0.isEmpty }

        if cleanedSegments.isEmpty {
            cleanedSegments = [cleanSegment(fullText)].filter { !$0.isEmpty }
        }

        let venueName = cleanedSegments.first
        let locationHint = cleanedSegments.dropFirst().first
        return (venueName, locationHint)
    }

    private nonisolated static func cleanSegment(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let removalPatterns = [
            #"(?i)\bopen\s*table\b"#,
            #"(?i)\bmake\s+a\s+reservation\s+for\s+me\b"#,
            #"(?i)\bbook\s+(?:me\s+)?(?:a\s+)?reservation\b"#,
            #"(?i)\bnavigate\s+to\b"#,
            #"(?i)\bopen\b"#,
            #"(?i)\bfind\b"#,
            #"(?i)\bshow\s+me\b"#,
            #"(?i)\bgo\s+to\b"#,
            #"(?i)\bpage\b"#,
            #"(?i)\bfor\s+me\b"#,
            #"(?i)\bon\b$"#
        ]

        for pattern in removalPatterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        value = value
            .replacingOccurrences(of: #"(?i)\bthe\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\s+people\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\s*(?:am|pm)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:today|tomorrow)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d{1,2}(?:st|nd|rd|th)?\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-").union(.whitespacesAndNewlines))

        let lowered = value.lowercased()
        if lowered.isEmpty {
            return ""
        }
        if ["on", "at", "for"].contains(lowered) {
            return ""
        }
        if lowered.contains("reservation") || lowered.contains("book") {
            return ""
        }
        if lowered == "opentable" || lowered == "open table" {
            return ""
        }
        return value
    }
}

struct GenericBrowserChatIntent: Equatable {
    let goalText: String
    let initialURL: String?
    let goalFocusTerms: [String]
    let providedData: BrowserSessionFollowUpData?

    nonisolated static func parse(_ text: String) -> GenericBrowserChatIntent? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let explicitURL = extractURL(from: normalized) {
            return GenericBrowserChatIntent(
                goalText: normalized,
                initialURL: normalizeURL(explicitURL),
                goalFocusTerms: [],
                providedData: BrowserSessionFollowUpParser.parse(text)
            )
        }

        let lowered = normalized.lowercased()
        let knownSites: [(needle: String, url: String)] = [
            ("opentable", "https://www.opentable.com"),
            ("booking.com", "https://www.booking.com"),
            ("expedia", "https://www.expedia.com"),
            ("kayak", "https://www.kayak.com"),
            ("google flights", "https://www.google.com/travel/flights"),
            ("airbnb", "https://www.airbnb.com"),
            ("amazon", "https://www.amazon.com")
        ]
        if let site = knownSites.first(where: { lowered.contains($0.needle) }) {
            return GenericBrowserChatIntent(
                goalText: normalized,
                initialURL: site.url,
                goalFocusTerms: [],
                providedData: BrowserSessionFollowUpParser.parse(text)
            )
        }

        let browserVerbs = ["open", "browse", "book", "find", "search", "look up", "go to", "navigate"]
        guard browserVerbs.contains(where: { lowered.contains($0) }) else {
            return nil
        }

        return GenericBrowserChatIntent(
            goalText: normalized,
            initialURL: nil,
            goalFocusTerms: [],
            providedData: BrowserSessionFollowUpParser.parse(text)
        )
    }

    private nonisolated static func extractURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector.firstMatch(in: text, options: [], range: range)
        return match?.url?.absoluteString
    }

    private nonisolated static func normalizeURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawValue }

        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme) else {
            return withScheme
        }
        if components.scheme == nil {
            components.scheme = "https"
        }
        if let host = components.host?.lowercased() {
            switch host {
            case "booking.com", "www.booking.com":
                components.scheme = "https"
                components.host = "www.booking.com"
            case "opentable.com", "www.opentable.com":
                components.scheme = "https"
                components.host = "www.opentable.com"
            default:
                break
            }
        }
        return components.string ?? withScheme
    }
}

struct BrowserApprovalResponse: Equatable {
    let approved: Bool
    let phoneNumber: String?
    let email: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let verificationCode: String?
    let consentDecision: Bool?
}

struct BrowserSessionFollowUpData: Equatable {
    let phoneNumber: String?
    let email: String?
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let verificationCode: String?
    let consentDecision: Bool?

    static let empty = BrowserSessionFollowUpData(
        phoneNumber: nil,
        email: nil,
        fullName: nil,
        firstName: nil,
        lastName: nil,
        addressLine1: nil,
        addressLine2: nil,
        city: nil,
        state: nil,
        postalCode: nil,
        country: nil,
        verificationCode: nil,
        consentDecision: nil
    )

    func merged(with newer: BrowserSessionFollowUpData?) -> BrowserSessionFollowUpData {
        guard let newer else { return self }
        return BrowserSessionFollowUpData(
            phoneNumber: newer.phoneNumber ?? phoneNumber,
            email: newer.email ?? email,
            fullName: newer.fullName ?? fullName,
            firstName: newer.firstName ?? firstName,
            lastName: newer.lastName ?? lastName,
            addressLine1: newer.addressLine1 ?? addressLine1,
            addressLine2: newer.addressLine2 ?? addressLine2,
            city: newer.city ?? city,
            state: newer.state ?? state,
            postalCode: newer.postalCode ?? postalCode,
            country: newer.country ?? country,
            verificationCode: newer.verificationCode ?? verificationCode,
            consentDecision: newer.consentDecision ?? consentDecision
        )
    }

    var isEmpty: Bool {
        phoneNumber == nil
            && email == nil
            && fullName == nil
            && firstName == nil
            && lastName == nil
            && addressLine1 == nil
            && addressLine2 == nil
            && city == nil
            && state == nil
            && postalCode == nil
            && country == nil
            && verificationCode == nil
            && consentDecision == nil
    }
}

struct BrowserApprovedContinuationContext: Equatable {
    let intent: GenericBrowserChatIntent
    let command: BrowserAgentCommand
    let approvalLabel: String
}

enum BrowserApprovedContinuationGuard {
    nonisolated static func matches(
        _ approved: BrowserApprovedContinuationContext?,
        command: BrowserAgentCommand?,
        inspection: ChromiumInspection?
    ) -> Bool {
        guard let approved, let command else { return false }
        if let inspection,
           let workflow = BrowserPageAnalyzer.workflow(for: inspection),
           (!workflow.requirements.isEmpty || !workflow.readyToContinue) {
            return false
        }

        let approvedSelector = normalized(approved.command.selector)
        let candidateSelector = normalized(command.selector)
        if let approvedSelector, let candidateSelector, approvedSelector == candidateSelector {
            return true
        }

        let approvedLabel = normalized(approved.approvalLabel)
        let candidateLabel = normalized(command.label ?? command.text ?? command.selector)
        if let approvedLabel, let candidateLabel, approvedLabel == candidateLabel {
            return true
        }

        if let boundary = inspection.flatMap(BrowserTransactionalGuard.highConfidenceFinalBoundary(in:)) {
            let boundarySelector = normalized(boundary.selector)
            if let approvedSelector, let boundarySelector, approvedSelector == boundarySelector {
                return true
            }
            let boundaryLabel = normalized(boundary.label)
            if let approvedLabel, let boundaryLabel, approvedLabel == boundaryLabel {
                return true
            }
        }

        return false
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

enum BrowserApprovalResponseParser {
    nonisolated static func parse(_ text: String) -> BrowserApprovalResponse? {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        let followUpData = BrowserSessionFollowUpParser.parse(text)

        let negativePhrases = [
            "no",
            "n",
            "reject",
            "decline",
            "cancel",
            "stop",
            "dont",
            "do not",
            "not now"
        ]
        if negativePhrases.contains(where: { matchesApprovalResponse(normalized, phrase: $0) }) {
            return BrowserApprovalResponse(
                approved: false,
                phoneNumber: followUpData?.phoneNumber,
                email: followUpData?.email,
                fullName: followUpData?.fullName,
                firstName: followUpData?.firstName,
                lastName: followUpData?.lastName,
                addressLine1: followUpData?.addressLine1,
                addressLine2: followUpData?.addressLine2,
                city: followUpData?.city,
                state: followUpData?.state,
                postalCode: followUpData?.postalCode,
                country: followUpData?.country,
                verificationCode: followUpData?.verificationCode,
                consentDecision: false
            )
        }

        let affirmativePhrases = [
            "yes",
            "y",
            "approve",
            "approved",
            "confirm",
            "confirm it",
            "go ahead",
            "proceed",
            "continue",
            "do it",
            "book it",
            "complete it",
            "make the reservation",
            "submit it"
        ]
        if affirmativePhrases.contains(where: { matchesApprovalResponse(normalized, phrase: $0) }) {
            return BrowserApprovalResponse(
                approved: true,
                phoneNumber: followUpData?.phoneNumber,
                email: followUpData?.email,
                fullName: followUpData?.fullName,
                firstName: followUpData?.firstName,
                lastName: followUpData?.lastName,
                addressLine1: followUpData?.addressLine1,
                addressLine2: followUpData?.addressLine2,
                city: followUpData?.city,
                state: followUpData?.state,
                postalCode: followUpData?.postalCode,
                country: followUpData?.country,
                verificationCode: followUpData?.verificationCode,
                consentDecision: followUpData?.consentDecision ?? true
            )
        }

        if followUpData != nil && (normalized.contains("book") || normalized.contains("reservation") || normalized.contains("complete") || normalized.contains("use")) {
            return BrowserApprovalResponse(
                approved: true,
                phoneNumber: followUpData?.phoneNumber,
                email: followUpData?.email,
                fullName: followUpData?.fullName,
                firstName: followUpData?.firstName,
                lastName: followUpData?.lastName,
                addressLine1: followUpData?.addressLine1,
                addressLine2: followUpData?.addressLine2,
                city: followUpData?.city,
                state: followUpData?.state,
                postalCode: followUpData?.postalCode,
                country: followUpData?.country,
                verificationCode: followUpData?.verificationCode,
                consentDecision: followUpData?.consentDecision
            )
        }

        return nil
    }

    nonisolated private static func matchesApprovalResponse(_ normalized: String, phrase: String) -> Bool {
        if phrase.count <= 2 {
            return normalized == phrase
        }
        return normalized == phrase || normalized.contains(phrase)
    }
}

enum BrowserSessionFollowUpParser {
    nonisolated static func parse(_ text: String) -> BrowserSessionFollowUpData? {
        let phoneNumber = extractPhoneNumber(from: text)
        let email = extractEmail(from: text)
        let fullName = extractNamedValue(from: text, patterns: [
            #"(?i)\b(?:my|use|full)\s*name\s*(?:is|:)?\s*([A-Za-z][A-Za-z'\-\s]{1,80})"#,
            #"(?i)\bname\s*(?:is|:)\s*([A-Za-z][A-Za-z'\-\s]{1,80})"#
        ])
        let firstName = extractNamedValue(from: text, patterns: [#"(?i)\bfirst\s*name\s*(?:is|:)?\s*([A-Za-z][A-Za-z'\-\s]{1,40})"#])
        let lastName = extractNamedValue(from: text, patterns: [#"(?i)\blast\s*name\s*(?:is|:)?\s*([A-Za-z][A-Za-z'\-\s]{1,40})"#])
        let addressLine1 = extractNamedValue(from: text, patterns: [
            #"(?i)\b(?:my\s+)?address\s*(?:is|:)?\s*([0-9A-Za-z][^\n]{4,120})"#,
            #"(?i)\b(?:street|shipping address|billing address)\s*(?:is|:)?\s*([0-9A-Za-z][^\n]{4,120})"#
        ])
        let addressLine2 = extractNamedValue(from: text, patterns: [
            #"(?i)\b(?:address line 2|apt|apartment|suite|unit)\s*(?:is|:)?\s*([0-9A-Za-z#\-]{1,20})"#
        ])
        let city = extractNamedValue(from: text, patterns: [#"(?i)\bcity\s*(?:is|:)?\s*([A-Za-z][A-Za-z'\-\s]{1,60})"#])
        let state = extractNamedValue(from: text, patterns: [#"(?i)\b(?:state|province|region)\s*(?:is|:)?\s*([A-Za-z][A-Za-z'\-\s]{1,60})"#])
        let postalCode = extractNamedValue(from: text, patterns: [#"(?i)\b(?:zip|postal(?:\s+code)?)\s*(?:is|:)?\s*([A-Za-z0-9\-\s]{3,16})"#])
        let country = extractNamedValue(from: text, patterns: [#"(?i)\bcountry\s*(?:is|:)?\s*([A-Za-z][A-Za-z'\-\s]{1,60})"#])
        let verificationCode = extractVerificationCode(from: text)
        let consentDecision = extractConsentDecision(from: text)
        guard phoneNumber != nil
            || email != nil
            || fullName != nil
            || firstName != nil
            || lastName != nil
            || addressLine1 != nil
            || addressLine2 != nil
            || city != nil
            || state != nil
            || postalCode != nil
            || country != nil
            || verificationCode != nil
            || consentDecision != nil else { return nil }
        return BrowserSessionFollowUpData(
            phoneNumber: phoneNumber,
            email: email,
            fullName: fullName,
            firstName: firstName,
            lastName: lastName,
            addressLine1: addressLine1,
            addressLine2: addressLine2,
            city: city,
            state: state,
            postalCode: postalCode,
            country: country,
            verificationCode: verificationCode,
            consentDecision: consentDecision
        )
    }

    nonisolated private static func extractPhoneNumber(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:\+?1[\s\-\.]?)?(?:\(?\d{3}\)?[\s\-\.]?)\d{3}[\s\-\.]?\d{4}"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        let digits = text[swiftRange].filter(\.isNumber)
        guard digits.count >= 10 else { return nil }
        return String(digits.suffix(10))
    }

    nonisolated private static func extractVerificationCode(from text: String) -> String? {
        let normalized = text.lowercased()
        let mentionsCode = normalized.contains("code")
            || normalized.contains("verification")
            || normalized.contains("otp")
            || normalized.contains("passcode")
            || normalized.contains("pin")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mentionsCode || (!trimmed.isEmpty && trimmed.allSatisfy(\.isNumber)) else {
            return nil
        }

        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{4,8})(?!\d)"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    nonisolated private static func extractEmail(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    nonisolated private static func extractNamedValue(from text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let value = text[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated private static func extractConsentDecision(from text: String) -> Bool? {
        let normalized = text.lowercased()
        let positive = ["agree", "accept", "yes", "allow", "opt in"]
        let negative = ["decline", "disagree", "do not", "don't", "dont", "no", "opt out"]
        if positive.contains(where: normalized.contains) {
            return true
        }
        if negative.contains(where: normalized.contains) {
            return false
        }
        return nil
    }
}

final class ChatSessionService: ChatSessionServicing {
    private struct PendingBrowserApprovalContext {
        let sessionID: UUID
        let intent: GenericBrowserChatIntent
        let command: BrowserAgentCommand
        let approvalLabel: String
        let latestInspection: ChromiumInspection?
        let inspectionHistory: [ChromiumInspection]
        let recentHistory: [String]
        let persistMessages: Bool
    }

    private struct PendingBrowserInputContext {
        let sessionID: UUID
        let personaID: String
        let intent: GenericBrowserChatIntent
        let latestInspection: ChromiumInspection?
        let inspectionHistory: [ChromiumInspection]
        let recentHistory: [String]
        let persistMessages: Bool
        let scenarioMetadata: BrowserScenarioMetadata?
        let knownFollowUpData: BrowserSessionFollowUpData
        let approvedContinuation: BrowserApprovedContinuationContext?
    }

    private struct BrowserLoopSeed {
        let latestInspection: ChromiumInspection?
        let inspectionHistory: [ChromiumInspection]
        let recentHistory: [String]
        let lastResultSummary: String
    }

    private struct BrowserAutonomousContinuationResult {
        let inspection: ChromiumInspection?
        let inspectionHistory: [ChromiumInspection]
        let recentHistory: [String]
        let statusLines: [String]
        let requiredInput: BrowserPageRequirement?
    }

    private let sessionStore: AssistantSessionStore
    private let personaManager: PersonaManager
    private let userProfileManager: UserProfileManager
    private let runtime: CodexRuntime
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let browserControllerProvider: @MainActor () -> ChromiumBrowserController

    private let stateLock = NSLock()
    private nonisolated(unsafe) var continuation: AsyncStream<ChatSessionEvent>.Continuation?
    private let pendingApprovalLock = NSLock()
    private nonisolated(unsafe) var pendingBrowserApproval: PendingBrowserApprovalContext?
    private let pendingInputLock = NSLock()
    private nonisolated(unsafe) var pendingBrowserInput: PendingBrowserInputContext?
    private let pendingInputMonitorLock = NSLock()
    private nonisolated(unsafe) var pendingBrowserInputMonitor: Task<Void, Never>?

    init(
        sessionStore: AssistantSessionStore,
        personaManager: PersonaManager,
        userProfileManager: UserProfileManager,
        runtime: CodexRuntime,
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore,
        browserControllerProvider: @escaping @MainActor () -> ChromiumBrowserController
    ) {
        self.sessionStore = sessionStore
        self.personaManager = personaManager
        self.userProfileManager = userProfileManager
        self.runtime = runtime
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
        self.browserControllerProvider = browserControllerProvider
    }

    func loadMessages() throws -> [Message] {
        try sessionStore.loadMessages()
    }

    func streamEvents() -> AsyncStream<ChatSessionEvent> {
        AsyncStream { continuation in
            stateLock.lock()
            self.continuation = continuation
            stateLock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.stateLock.lock()
                self.continuation = nil
                self.stateLock.unlock()
            }
        }
    }

    func cancelCurrentRun() throws {
        try runtime.cancelCurrentRun()
    }

    func sendUserMessage(_ text: String) async throws {
        defer { finishStream() }

        let persona = try personaManager.defaultPersona()
        var session = try sessionStore.loadOrCreateDefault(personaId: persona.id)

        let userMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .user,
            text: text,
            source: .userInput,
            createdAt: Date()
        )
        try sessionStore.appendMessage(userMessage)

        if let pendingInput = pendingBrowserInputContext(for: session.id) {
            let followUp = BrowserSessionFollowUpParser.parse(text)
            _ = try await handlePendingBrowserInputResponse(
                text: text,
                followUp: followUp,
                pendingInput,
                persona: persona,
                session: &session
            )
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

        if let pendingApproval = pendingBrowserApprovalContext(for: session.id) {
            if let approved = BrowserApprovalResponseParser.parse(text) {
                _ = try await handlePendingBrowserApprovalResponse(
                    response: approved,
                    pendingApproval,
                    persona: persona,
                    session: &session
                )
                session.updatedAt = Date()
                try sessionStore.save(session)
                emit(.completed)
                return
            }

            let reminder = approvalPrompt(for: pendingApproval.approvalLabel, inspection: pendingApproval.latestInspection)
            try emitAssistantMessage(reminder, session: session, shouldStore: true)
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

        if let followUp = BrowserSessionFollowUpParser.parse(text),
           try await handleActiveBrowserFollowUp(followUp, session: &session) {
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

        if try await handleActiveBrowserVerificationMessageIfNeeded(text, session: &session) {
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

        if let browserIntent = ChatBrowserIntent.parse(text) {
            try await handleBrowserIntent(browserIntent, session: &session)
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

        if let genericBrowserIntent = GenericBrowserChatIntent.parse(text) {
            _ = try await handleGenericBrowserIntent(genericBrowserIntent, persona: persona, session: &session)
            session.updatedAt = Date()
            try sessionStore.save(session)
            emit(.completed)
            return
        }

        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: .chatOnly,
            externalDirectory: nil,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )

        let prompt = buildChatPrompt(userText: text)
        let runtimeStream = runtime.streamEvents()

        var assistantText = ""
        var streamedDisplayText = ""
        var stderrText = ""

        let bridgeTask = Task {
            for await event in runtimeStream {
                switch event {
                case let .stdoutLine(line):
                    assistantText += assistantText.isEmpty ? line : "\n\(line)"
                    let sanitizedLine = nextSanitizedAssistantDelta(
                        from: assistantText,
                        previousDisplayText: &streamedDisplayText
                    )
                    if !sanitizedLine.isEmpty {
                        emit(.assistantDelta(sanitizedLine))
                    }
                case let .stderrLine(line):
                    stderrText += stderrText.isEmpty ? line : "\n\(line)"
                    emit(.stderr(line))
                case let .threadIdentified(threadId):
                    session.codexThreadId = threadId
                    session.updatedAt = Date()
                    try? sessionStore.save(session)
                case .started, .completed:
                    break
                case let .failed(message):
                    emit(.failed(message))
                }
            }
        }

        let result: CodexExecutionResult
        if let threadId = session.codexThreadId {
            result = try await runtime.resumeThread(threadId: threadId, prompt: prompt, config: launchConfig)
        } else {
            result = try await runtime.startNewThread(prompt: prompt, config: launchConfig)
            if let threadId = result.threadId {
                session.codexThreadId = threadId
            }
        }

        _ = await bridgeTask.result

        session.updatedAt = Date()
        try sessionStore.save(session)

        let parsed = parseAssistantResponse(assistantText)
        let assistantMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            text: parsed.displayText.isEmpty ? assistantText : parsed.displayText,
            source: .codexStdout,
            createdAt: Date()
        )
        try sessionStore.appendMessage(assistantMessage)

        if let proposal = parsed.proposal {
            emit(.proposal(proposal))
        }

        if result.exitCode != 0 {
            let message = stderrText.isEmpty ? "Chat failed with exit code \(result.exitCode)" : stderrText
            emit(.failed(message))
            return
        }

        emit(.completed)
    }

    func runBrowserScenario(_ scenario: BrowserSmokeScenarioDefinition) async throws -> BrowserScenarioRunSummary {
        defer { finishStream() }

        let persona = try personaManager.defaultPersona()
        var session = AssistantSession(
            id: UUID(),
            codexThreadId: nil,
            personaId: persona.id,
            mode: .chatOnly,
            createdAt: Date(),
            updatedAt: Date()
        )
        let metadata = BrowserScenarioMetadata(
            id: scenario.id,
            title: scenario.title,
            category: scenario.category
        )

        emit(.assistantMessage("Running browser smoke scenario \(scenario.id) (\(scenario.category))."))

        if let browserIntent = ChatBrowserIntent.parse(scenario.goalText) {
            let result = try await handleGenericBrowserIntent(
                browserIntent.genericBrowserIntent,
                persona: persona,
                session: &session,
                persistMessages: false,
                scenarioMetadata: metadata
            )
            emit(.completed)
            return result
        }

        if let genericBrowserIntent = GenericBrowserChatIntent.parse(scenario.goalText) {
            let result = try await handleGenericBrowserIntent(
                genericBrowserIntent,
                persona: persona,
                session: &session,
                persistMessages: false,
                scenarioMetadata: metadata
            )
            emit(.completed)
            return BrowserScenarioRunSummary(
                scenarioID: scenario.id,
                category: scenario.category,
                outcome: result.outcome,
                finalSummary: result.finalSummary
            )
        }

        throw ChromiumBrowserActionError(message: "Scenario \(scenario.id) does not parse into a browser intent.")
    }

    @discardableResult
    private func handleBrowserIntent(
        _ intent: ChatBrowserIntent,
        session: inout AssistantSession,
        persistMessages: Bool = true,
        scenarioMetadata: BrowserScenarioMetadata? = nil
    ) async throws -> String {
        let persona = try personaManager.defaultPersona()
        let result = try await handleGenericBrowserIntent(
            intent.genericBrowserIntent,
            persona: persona,
            session: &session,
            persistMessages: persistMessages,
            scenarioMetadata: scenarioMetadata
        )
        return result.finalSummary
    }

    private func handleGenericBrowserIntent(
        _ intent: GenericBrowserChatIntent,
        persona: Persona,
        session: inout AssistantSession,
        persistMessages: Bool = true,
        scenarioMetadata: BrowserScenarioMetadata? = nil
    ) async throws -> BrowserScenarioRunSummary {
        let browserController = await MainActor.run { browserControllerProvider() }

        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: .chatOnly,
            externalDirectory: nil,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )
        return try await runGenericBrowserLoop(
            intent,
            session: &session,
            controller: browserController,
            launchConfig: launchConfig,
            persistMessages: persistMessages,
            scenarioMetadata: scenarioMetadata,
            seed: BrowserLoopSeed(
                latestInspection: nil,
                inspectionHistory: [],
                recentHistory: [],
                lastResultSummary: intent.initialURL != nil
                    ? "The browser can open \(intent.initialURL!)."
                    : "No browser action has run yet."
            )
        )
    }

    private func handleActiveBrowserFollowUp(
        _ followUp: BrowserSessionFollowUpData,
        session: inout AssistantSession
    ) async throws -> Bool {
        let browserController = await MainActor.run { browserControllerProvider() }
        guard let currentInspection = try? await browserController.inspectCurrentPageForAgent(),
              currentInspection.url != "about:blank" else {
            return false
        }

        var updatedInspection = currentInspection
        var statusLines: [String] = []
        var handled = false

        let currentRequirements = pageRequirements(for: updatedInspection)
        for requirement in currentRequirements {
            if requirement.kind == "verification_code" {
                continue
            }
            guard let value = followUpValue(for: requirement, followUp: followUp) else { continue }
            try await applyRequirement(requirement, value: value, controller: browserController)
            updatedInspection = try await browserController.inspectCurrentPageForAgent()
            statusLines.append("Filled the required \(humanReadableRequirementLabel(requirement)) in the current browser page.")
            handled = true
        }

        if let verificationCode = followUp.verificationCode {
            do {
                _ = try await browserController.typeVerificationCodeForAgent(verificationCode)
                updatedInspection = try await settleAndInspectAfterVerificationInput(
                    controller: browserController,
                    fallback: try await browserController.inspectCurrentPageForAgent()
                ) ?? updatedInspection
                statusLines.append("Entered the verification code in the current browser page.")
                handled = true
                if let advanced = try await advanceVerificationStepIfPossible(
                    inspection: updatedInspection,
                    controller: browserController
                ) {
                    updatedInspection = try await settleAndInspectAfterVerificationInput(
                        controller: browserController,
                        fallback: advanced.inspection
                    ) ?? advanced.inspection
                    statusLines.append(advanced.summary)
                }
            } catch let error as ChromiumBrowserActionError {
                if !handled && error.message.lowercased().contains("no visible verification field found") {
                    return false
                }
                throw error
            }
        }

        guard handled else { return false }

        if let pendingCommand = pendingApprovalCommand(from: updatedInspection),
           let approvalLabel = approvalBoundaryLabelIfNeeded(for: pendingCommand, inspection: updatedInspection) {
            let continuationIntent = GenericBrowserChatIntent(
                goalText: "Continue the current browser booking flow safely in the existing session and stop before any final confirmation step unless explicitly approved.",
                initialURL: nil,
                goalFocusTerms: [],
                providedData: nil
            )
            setPendingBrowserApproval(
                PendingBrowserApprovalContext(
                    sessionID: session.id,
                    intent: continuationIntent,
                    command: pendingCommand,
                    approvalLabel: approvalLabel,
                    latestInspection: updatedInspection,
                    inspectionHistory: [updatedInspection],
                    recentHistory: statusLines,
                    persistMessages: true
                )
            )
            let prefix = statusLines.joined(separator: " ")
            let prompt = approvalPrompt(for: approvalLabel, inspection: updatedInspection)
            let combined = prefix.isEmpty ? prompt : "\(prefix) \(prompt)"
            try emitAssistantMessage(combined, session: session, shouldStore: true)
            return true
        }

        guard handled else { return false }
        if let verificationPrompt = await verificationFollowUpPromptIfNeeded(
            inspection: updatedInspection,
            controller: browserController
        ) {
            try emitAssistantMessage(verificationPrompt, session: session, shouldStore: true)
            return true
        }
        let message = await userFacingBrowserStateMessage(
            inspection: updatedInspection,
            controller: browserController
        ) ?? "I updated the active browser page and I’m continuing in the same session."
        try emitAssistantMessage(message, session: session, shouldStore: true)
        return true
    }

    private func handleActiveBrowserVerificationMessageIfNeeded(
        _ text: String,
        session: inout AssistantSession
    ) async throws -> Bool {
        guard messageMentionsVerificationCode(text) else { return false }

        let browserController = await MainActor.run { browserControllerProvider() }
        guard let inspection = try? await browserController.inspectCurrentPageForAgent(),
              inspection.url != "about:blank",
              requiresVerificationCode(for: inspection) else {
            return false
        }

        let reminder = browserInputPrompt(
            for: BrowserPageRequirement(
                id: "active-browser-verification-code",
                kind: "verification_code",
                label: "Verification code",
                selector: nil,
                controlType: "one-time-code",
                fillAction: "type_text",
                options: [],
                prompt: "I still need the verification code for this page.",
                isSensitive: true,
                priority: 145,
                validationMessage: "The current page is waiting on a verification step."
            ),
            inspection: inspection
        )
        try emitAssistantMessage(reminder, session: session, shouldStore: true)
        return true
    }

    private func buildChatPrompt(userText: String) -> String {
        """
        FORMAT INSTRUCTION:
        If and only if the user is clearly asking to create a recurring or background task, append exactly one XML block at the end of your response:
        <agenthub_task_proposal>{"title":"...","instructions":"...","scheduleType":"manual|intervalMinutes|dailyAtHHMM","scheduleValue":"...","runtimeMode":"chatOnly|task","repoPath":null,"runNow":false}</agenthub_task_proposal>
        Do not mention the XML block in your prose.
        Do not restate or override instructions already provided by AGENTS.md.

        USER:
        \(userText)
        """
    }

    private func handlePendingBrowserApprovalResponse(
        response: BrowserApprovalResponse,
        _ pending: PendingBrowserApprovalContext,
        persona: Persona,
        session: inout AssistantSession
    ) async throws -> BrowserScenarioRunSummary {
        let browserController = await MainActor.run { browserControllerProvider() }
        let currentInspection = try? await browserController.inspectCurrentPageForAgent()

        guard response.approved else {
            clearPendingBrowserApproval(for: pending.sessionID)
            let finalText = "Cancelled the final confirmation step for \"\(pending.approvalLabel)\". No transaction was submitted."
            try await persistBrowserRunArtifacts(
                outcome: "approval_rejected",
                goalText: pending.intent.goalText,
                initialURL: pending.intent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: pending.inspectionHistory,
                recentHistory: pending.recentHistory,
                finalSummary: finalText
            )
            try emitAssistantMessage(finalText, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: "ad_hoc",
                category: BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
                outcome: "approval_rejected",
                finalSummary: finalText
            )
        }

        let approvalFollowUp = BrowserSessionFollowUpData(
            phoneNumber: response.phoneNumber,
            email: response.email,
            fullName: response.fullName,
            firstName: response.firstName,
            lastName: response.lastName,
            addressLine1: response.addressLine1,
            addressLine2: response.addressLine2,
            city: response.city,
            state: response.state,
            postalCode: response.postalCode,
            country: response.country,
            verificationCode: response.verificationCode,
            consentDecision: response.consentDecision
        )
        let approvedIntent = GenericBrowserChatIntent(
            goalText: pending.intent.goalText,
            initialURL: pending.intent.initialURL,
            goalFocusTerms: pending.intent.goalFocusTerms,
            providedData: (pending.intent.providedData ?? .empty).merged(with: approvalFollowUp)
        )
        let knownApprovalData = mergedKnownFollowUpData(
            personaID: session.personaId,
            providedData: approvedIntent.providedData
        ) ?? .empty

        let inspectionForRequirements = currentInspection ?? pending.latestInspection
        let missingRequirement = primaryUserRequirement(in: inspectionForRequirements)
        if let missingRequirement,
           followUpValue(
                for: missingRequirement,
                followUp: knownApprovalData
           ) == nil {
            setPendingBrowserApproval(
                PendingBrowserApprovalContext(
                    sessionID: pending.sessionID,
                    intent: pending.intent,
                    command: pending.command,
                    approvalLabel: pending.approvalLabel,
                    latestInspection: inspectionForRequirements,
                    inspectionHistory: pending.inspectionHistory,
                    recentHistory: pending.recentHistory,
                    persistMessages: pending.persistMessages
                )
            )
            let reminder = "I still need more information before I can complete \"\(pending.approvalLabel)\". \(missingRequirement.prompt) Reply `yes` and include it, or `no` to cancel."
            try emitAssistantMessage(reminder, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: "ad_hoc",
                category: BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
                outcome: "awaiting_user_approval",
                finalSummary: reminder
            )
        }

        clearPendingBrowserApproval(for: pending.sessionID)
        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: .chatOnly,
            externalDirectory: nil,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )

        var inspectionHistory = pending.inspectionHistory
        var recentHistory = pending.recentHistory
        let approvedContinuation = BrowserApprovedContinuationContext(
            intent: approvedIntent,
            command: pending.command,
            approvalLabel: pending.approvalLabel
        )
        let applicableRequirements = pageRequirements(for: inspectionForRequirements)
        for requirement in applicableRequirements {
            guard let value = followUpValue(for: requirement, followUp: knownApprovalData) else { continue }
            try await applyRequirement(requirement, value: value, controller: browserController)
            let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
            inspectionHistory.append(refreshedInspection)
            if inspectionHistory.count > 20 {
                inspectionHistory.removeFirst(inspectionHistory.count - 20)
            }
            recentHistory.append("Filled required \(humanReadableRequirementLabel(requirement)) before the approved final step.")
            if recentHistory.count > 6 {
                recentHistory.removeFirst(recentHistory.count - 6)
            }
        }

        let latestApprovalInspection = try await browserController.inspectCurrentPageForAgent()
        inspectionHistory.append(latestApprovalInspection)
        if inspectionHistory.count > 20 {
            inspectionHistory.removeFirst(inspectionHistory.count - 20)
        }

        let execution: BrowserAgentExecutionResult?
        if BrowserApprovedContinuationGuard.matches(
            approvedContinuation,
            command: pending.command,
            inspection: latestApprovalInspection
        ) {
            execution = try await executePendingApprovedBrowserCommand(
                pending.command,
                intent: approvedIntent,
                inspection: latestApprovalInspection,
                controller: browserController
            )
        } else {
            execution = nil
            recentHistory.append("Skipped the stale approved final step because the page now needs more input before it can continue.")
            if recentHistory.count > 6 {
                recentHistory.removeFirst(recentHistory.count - 6)
            }
        }

        var postApprovalInspection: ChromiumInspection? = execution?.inspection ?? latestApprovalInspection
        if let execution, let inspection = execution.inspection {
            inspectionHistory.append(inspection)
            if inspectionHistory.count > 20 {
                inspectionHistory.removeFirst(inspectionHistory.count - 20)
            }
            recentHistory.append("Approved final step: \(pending.command.action.rawValue) -> \(execution.summary)")
            if recentHistory.count > 6 {
                recentHistory.removeFirst(recentHistory.count - 6)
            }
        }

        postApprovalInspection = try await settleAndInspectAfterApprovedAction(
            controller: browserController,
            fallback: postApprovalInspection ?? inspectionHistory.last ?? inspectionForRequirements,
            approvedContinuation: approvedContinuation
        )
        if let postApprovalInspection {
            inspectionHistory.append(postApprovalInspection)
            if inspectionHistory.count > 20 {
                inspectionHistory.removeFirst(inspectionHistory.count - 20)
            }
        }

        let knownFollowUpData = knownApprovalData
        let continuation = try await continueBrowserAutonomouslyUntilBlocked(
            inspection: postApprovalInspection,
            personaID: session.personaId,
            knownData: knownFollowUpData,
            controller: browserController,
            inspectionHistory: inspectionHistory,
            recentHistory: recentHistory
        )
        postApprovalInspection = continuation.inspection
        inspectionHistory = continuation.inspectionHistory
        recentHistory = continuation.recentHistory
        if let requirement = continuation.requiredInput,
           followUpValue(for: requirement, followUp: knownFollowUpData) == nil {
            let prompt = await promptForRequiredBrowserInput(
                requirement,
                inspection: postApprovalInspection,
                controller: browserController
            )
            setPendingBrowserInput(
                PendingBrowserInputContext(
                    sessionID: pending.sessionID,
                    personaID: session.personaId,
                    intent: approvedIntent,
                    latestInspection: postApprovalInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    persistMessages: pending.persistMessages,
                    scenarioMetadata: nil,
                    knownFollowUpData: knownFollowUpData,
                    approvedContinuation: approvedContinuation
                )
            )
            try await persistBrowserRunArtifacts(
                outcome: "awaiting_user_input",
                goalText: approvedIntent.goalText,
                initialURL: approvedIntent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: prompt
            )
            try emitAssistantMessage(prompt, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: "ad_hoc",
                category: BrowserScenarioClassifier.category(forGoalText: approvedIntent.goalText, initialURL: approvedIntent.initialURL),
                outcome: "awaiting_user_input",
                finalSummary: prompt
            )
        }

        if execution != nil,
           let requirement = BrowserPageAnalyzer.followUpRequirementAfterApprovedFinalAction(
                currentInspection: postApprovalInspection,
                priorInspection: latestApprovalInspection
           ) {
            let prompt = await promptForRequiredBrowserInput(
                requirement,
                inspection: postApprovalInspection,
                controller: browserController
            )
            setPendingBrowserInput(
                PendingBrowserInputContext(
                    sessionID: pending.sessionID,
                    personaID: session.personaId,
                    intent: approvedIntent,
                    latestInspection: postApprovalInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    persistMessages: pending.persistMessages,
                    scenarioMetadata: nil,
                    knownFollowUpData: knownFollowUpData,
                    approvedContinuation: approvedContinuation
                )
            )
            try await persistBrowserRunArtifacts(
                outcome: "awaiting_user_input",
                goalText: approvedIntent.goalText,
                initialURL: approvedIntent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: prompt
            )
            try emitAssistantMessage(prompt, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: "ad_hoc",
                category: BrowserScenarioClassifier.category(forGoalText: approvedIntent.goalText, initialURL: approvedIntent.initialURL),
                outcome: "awaiting_user_input",
                finalSummary: prompt
            )
        }

        return try await runGenericBrowserLoop(
            approvedIntent,
            session: &session,
            controller: browserController,
            launchConfig: launchConfig,
            persistMessages: pending.persistMessages,
            scenarioMetadata: nil,
            seed: BrowserLoopSeed(
                latestInspection: postApprovalInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                lastResultSummary: execution?.summary ?? "Approval was received, but the page still required more input before any final confirmation could continue."
            ),
            approvedContinuation: approvedContinuation
        )
    }

    private func approvalPrompt(for approvalLabel: String, inspection: ChromiumInspection?) -> String {
        if let requirement = primaryUserRequirement(in: inspection) {
            return "I’m at the final confirmation step for \"\(approvalLabel)\". \(requirement.prompt) Reply `yes` and include it, or `no` to cancel."
        }
        if BrowserPageAnalyzer.finalBoundaryMayTriggerVerification(for: inspection) {
            return "I’m at the approval boundary for \"\(approvalLabel)\". Reply `yes` to continue. This action may immediately open a verification step, and I’ll pause again if the site asks for a code."
        }
        return "I’m at the final confirmation step for \"\(approvalLabel)\". Reply `yes` to complete it or `no` to cancel."
    }

    private func settleAndInspectAfterApprovedAction(
        controller: ChromiumBrowserController,
        fallback: ChromiumInspection?,
        approvedContinuation: BrowserApprovedContinuationContext
    ) async throws -> ChromiumInspection? {
        var latestInspection = fallback
        if latestInspection == nil {
            latestInspection = try? await controller.inspectCurrentPageForAgent()
        }

        for attempt in 0..<6 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            do {
                _ = try await controller.waitForSettleForAgent(timeout: 2.5)
            } catch {
                // Keep polling inspection even if settle times out.
            }

            guard let refreshedInspection = try? await controller.inspectCurrentPageForAgent() else {
                continue
            }
            latestInspection = refreshedInspection

            if nextPromptableRequirement(in: refreshedInspection) != nil {
                break
            }
            if let workflow = BrowserPageAnalyzer.workflow(for: refreshedInspection),
               workflow.hasSuccessSignal || workflow.hasFailureSignal || workflow.stage == "verification" {
                break
            }
            if !BrowserApprovedContinuationGuard.matches(
                approvedContinuation,
                command: pendingApprovalCommand(from: refreshedInspection),
                inspection: refreshedInspection
            ) {
                break
            }
        }

        if let latestInspection,
           BrowserPageAnalyzer.finalBoundaryMayTriggerVerification(for: fallback ?? latestInspection),
           nextPromptableRequirement(in: latestInspection) == nil,
           let visuallyAugmented = try? await visuallyAugmentedInspectionAfterApprovedAction(
                latestInspection,
                fallback: fallback,
                controller: controller
           ) {
            return visuallyAugmented
        }

        return latestInspection
    }

    private func visuallyAugmentedInspectionAfterApprovedAction(
        _ inspection: ChromiumInspection,
        fallback: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async throws -> ChromiumInspection {
        let artifact = try await controller.captureScrolledSnapshotForAgent(label: "approved-final")
        guard let recognizedText = artifact.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !recognizedText.isEmpty else {
            return inspection
        }
        return BrowserPageAnalyzer.augmentInspection(
            inspection,
            withVisualRecognitionText: recognizedText,
            fallback: fallback
        )
    }

    private func handlePendingBrowserInputResponse(
        text: String,
        followUp: BrowserSessionFollowUpData?,
        _ pending: PendingBrowserInputContext,
        persona: Persona,
        session: inout AssistantSession
    ) async throws -> BrowserScenarioRunSummary {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if followUp == nil, ["cancel", "stop", "never mind", "no"].contains(where: normalized.contains) {
            clearPendingBrowserInput(for: pending.sessionID)
            let finalText = "Cancelled the current browser flow before submitting anything."
            try await persistBrowserRunArtifacts(
                outcome: "input_cancelled",
                goalText: pending.intent.goalText,
                initialURL: pending.intent.initialURL,
                session: session,
                controller: await MainActor.run { browserControllerProvider() },
                inspectionHistory: pending.inspectionHistory,
                recentHistory: pending.recentHistory,
                finalSummary: finalText,
                scenarioMetadata: pending.scenarioMetadata
            )
            try emitAssistantMessage(finalText, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: pending.scenarioMetadata?.id ?? "ad_hoc",
                category: pending.scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
                outcome: "input_cancelled",
                finalSummary: finalText
            )
        }

        let browserController = await MainActor.run { browserControllerProvider() }
        var latestInspection = try? await browserController.inspectCurrentPageForAgent()
        var inspectionHistory = pending.inspectionHistory
        var recentHistory = pending.recentHistory
        let combinedData = pending.knownFollowUpData.merged(with: followUp)
        var verificationCodeWasApplied = false
        var preserveVerificationContext = shouldPreserveVerificationContext(
            currentInspection: latestInspection,
            pendingInspection: pending.latestInspection
        )

        if followUp?.verificationCode != nil || shouldPrioritizeVerificationOnly(in: pending.latestInspection) {
            latestInspection = await refreshVerificationInspectionIfNeeded(
                currentInspection: latestInspection,
                fallback: pending.latestInspection,
                controller: browserController
            )
            preserveVerificationContext = shouldPreserveVerificationContext(
                currentInspection: latestInspection,
                pendingInspection: pending.latestInspection
            )
        }

        if followUp?.consentDecision == false,
           nextPromptableRequirement(in: latestInspection)?.kind == "consent" {
            clearPendingBrowserInput(for: pending.sessionID)
            let finalText = "Cancelled the current browser flow because the required consent was declined."
            try await persistBrowserRunArtifacts(
                outcome: "input_cancelled",
                goalText: pending.intent.goalText,
                initialURL: pending.intent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: finalText,
                scenarioMetadata: pending.scenarioMetadata
            )
            try emitAssistantMessage(finalText, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: pending.scenarioMetadata?.id ?? "ad_hoc",
                category: pending.scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
                outcome: "input_cancelled",
                finalSummary: finalText
            )
        }

        do {
            if let applied = try await applyFollowUpDataToBrowser(
                    inspection: latestInspection,
                    followUp: combinedData,
                    controller: browserController,
                    includeVerificationCode: true,
                    forceVerificationOnly: preserveVerificationContext
               ) {
                verificationCodeWasApplied = applied.statusLines.contains { $0.localizedCaseInsensitiveContains("Entered the verification code") }
                latestInspection = applied.inspection
                preserveVerificationContext = shouldPreserveVerificationContext(
                    currentInspection: latestInspection,
                    pendingInspection: pending.latestInspection
                )
                inspectionHistory.append(applied.inspection)
                if inspectionHistory.count > 20 {
                    inspectionHistory.removeFirst(inspectionHistory.count - 20)
                }
                recentHistory.append(contentsOf: applied.statusLines)
                if recentHistory.count > 6 {
                    recentHistory.removeFirst(recentHistory.count - 6)
                }
            }
        } catch let error as ChromiumBrowserActionError
            where followUp?.verificationCode != nil
                && error.message.lowercased().contains("verification field") {
            latestInspection = await refreshVerificationInspectionIfNeeded(
                currentInspection: latestInspection,
                fallback: pending.latestInspection,
                controller: browserController
            )
            return try await returnAwaitingVerificationInput(
                pending,
                requirement: BrowserPageRequirement(
                    id: "verification-code-retry",
                    kind: "verification_code",
                    label: "Verification code",
                    selector: nil,
                    controlType: "one-time-code",
                    fillAction: "type_text",
                    options: [],
                    prompt: "I still need the verification code for this page.",
                    isSensitive: true,
                    priority: 145,
                    validationMessage: error.message
                ),
                latestInspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                combinedData: combinedData,
                session: &session,
                controller: browserController
            )
        }

        let continuation = try await continueBrowserAutonomouslyUntilBlocked(
            inspection: latestInspection ?? pending.latestInspection,
            personaID: session.personaId,
            knownData: combinedData,
            controller: browserController,
            inspectionHistory: inspectionHistory,
            recentHistory: recentHistory
        )
        latestInspection = continuation.inspection
        inspectionHistory = continuation.inspectionHistory
        recentHistory = continuation.recentHistory
        if combinedData.verificationCode != nil || shouldPrioritizeVerificationOnly(in: pending.latestInspection) {
            latestInspection = await refreshVerificationInspectionIfNeeded(
                currentInspection: latestInspection,
                fallback: pending.latestInspection,
                controller: browserController
            )
            preserveVerificationContext = shouldPreserveVerificationContext(
                currentInspection: latestInspection,
                pendingInspection: pending.latestInspection
            )
            if let latestInspection {
                inspectionHistory.append(latestInspection)
                if inspectionHistory.count > 20 {
                    inspectionHistory.removeFirst(inspectionHistory.count - 20)
                }
            }
        }

        if let requirement = continuation.requiredInput,
           followUpValue(for: requirement, followUp: combinedData) == nil {
            return try await returnAwaitingVerificationInput(
                pending,
                requirement: requirement,
                latestInspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                combinedData: combinedData,
                session: &session,
                controller: browserController
            )
        }

        if let requirement = continuation.requiredInput,
           requirement.kind == "verification_code",
           combinedData.verificationCode != nil {
            if let verificationPrompt = await verificationFollowUpPromptIfNeeded(
                inspection: latestInspection,
                controller: browserController
            ) {
                clearPendingBrowserApproval(for: pending.sessionID)
                setPendingBrowserInput(
                    PendingBrowserInputContext(
                        sessionID: pending.sessionID,
                        personaID: session.personaId,
                        intent: pending.intent,
                        latestInspection: latestInspection,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        persistMessages: pending.persistMessages,
                        scenarioMetadata: pending.scenarioMetadata,
                        knownFollowUpData: combinedData,
                        approvedContinuation: pending.approvedContinuation
                    )
                )
                try await persistBrowserRunArtifacts(
                    outcome: "awaiting_user_input",
                    goalText: pending.intent.goalText,
                    initialURL: pending.intent.initialURL,
                    session: session,
                    controller: browserController,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    finalSummary: verificationPrompt,
                    scenarioMetadata: pending.scenarioMetadata
                )
                try emitAssistantMessage(verificationPrompt, session: session, shouldStore: pending.persistMessages)
                return BrowserScenarioRunSummary(
                    scenarioID: pending.scenarioMetadata?.id ?? "ad_hoc",
                    category: pending.scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
                    outcome: "awaiting_user_input",
                    finalSummary: verificationPrompt
                )
            }
        }

        if combinedData.verificationCode != nil,
           !verificationCodeWasApplied,
           preserveVerificationContext {
            return try await returnAwaitingVerificationInput(
                pending,
                requirement: BrowserPageRequirement(
                    id: "verification-code-not-applied",
                    kind: "verification_code",
                    label: "Verification code",
                    selector: nil,
                    controlType: "one-time-code",
                    fillAction: "type_text",
                    options: [],
                    prompt: "I still need the verification code for this page.",
                    isSensitive: true,
                    priority: 145,
                    validationMessage: "The verification field was not ready for the last code."
                ),
                latestInspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                combinedData: combinedData,
                session: &session,
                controller: browserController
            )
        }

        if combinedData.verificationCode != nil,
           preserveVerificationContext,
           let verificationPrompt = await verificationFollowUpPromptIfNeeded(
               inspection: latestInspection ?? pending.latestInspection,
               controller: browserController
           ) {
            clearPendingBrowserApproval(for: pending.sessionID)
            setPendingBrowserInput(
                PendingBrowserInputContext(
                    sessionID: pending.sessionID,
                    personaID: session.personaId,
                    intent: pending.intent,
                    latestInspection: latestInspection ?? pending.latestInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    persistMessages: pending.persistMessages,
                    scenarioMetadata: pending.scenarioMetadata,
                    knownFollowUpData: combinedData,
                    approvedContinuation: pending.approvedContinuation
                )
            )
            try await persistBrowserRunArtifacts(
                outcome: "awaiting_user_input",
                goalText: pending.intent.goalText,
                initialURL: pending.intent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: verificationPrompt,
                scenarioMetadata: pending.scenarioMetadata
            )
            try emitAssistantMessage(verificationPrompt, session: session, shouldStore: pending.persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: pending.scenarioMetadata?.id ?? "ad_hoc",
                category: pending.scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
                outcome: "awaiting_user_input",
                finalSummary: verificationPrompt
            )
        }

        clearPendingBrowserInput(for: pending.sessionID)
        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: .chatOnly,
            externalDirectory: nil,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )

        return try await runGenericBrowserLoop(
            GenericBrowserChatIntent(
                goalText: pending.intent.goalText,
                initialURL: pending.intent.initialURL,
                goalFocusTerms: pending.intent.goalFocusTerms,
                providedData: combinedData
            ),
            session: &session,
            controller: browserController,
            launchConfig: launchConfig,
            persistMessages: pending.persistMessages,
            scenarioMetadata: pending.scenarioMetadata,
            seed: BrowserLoopSeed(
                latestInspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                lastResultSummary: recentHistory.last ?? "Filled the requested information in the active browser session."
            ),
            approvedContinuation: pending.approvedContinuation
        )
    }

    private func refreshVerificationInspectionIfNeeded(
        currentInspection: ChromiumInspection?,
        fallback: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async -> ChromiumInspection? {
        let baseline = currentInspection ?? fallback
        guard let baseline else { return currentInspection }
        let shouldRefresh = verificationRefreshNeeded(for: currentInspection)
            || verificationRefreshNeeded(for: fallback)
        guard shouldRefresh else { return currentInspection ?? fallback }
        guard let artifact = try? await controller.captureScrolledSnapshotForAgent(label: "verification-state"),
              let recognizedText = artifact.recognizedText,
              !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return currentInspection ?? fallback
        }
        return BrowserPageAnalyzer.augmentInspection(
            currentInspection ?? baseline,
            withVisualRecognitionText: recognizedText,
            fallback: fallback
        )
    }

    private func verificationRefreshNeeded(for inspection: ChromiumInspection?) -> Bool {
        BrowserPageAnalyzer.canonicalState(for: inspection)?.requiresVisualRefresh ?? false
    }

    private func returnAwaitingVerificationInput(
        _ pending: PendingBrowserInputContext,
        requirement: BrowserPageRequirement,
        latestInspection: ChromiumInspection?,
        inspectionHistory: [ChromiumInspection],
        recentHistory: [String],
        combinedData: BrowserSessionFollowUpData,
        session: inout AssistantSession,
        controller browserController: ChromiumBrowserController
    ) async throws -> BrowserScenarioRunSummary {
        clearPendingBrowserApproval(for: pending.sessionID)
        setPendingBrowserInput(
            PendingBrowserInputContext(
                sessionID: pending.sessionID,
                personaID: session.personaId,
                intent: pending.intent,
                latestInspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                persistMessages: pending.persistMessages,
                scenarioMetadata: pending.scenarioMetadata,
                knownFollowUpData: combinedData,
                approvedContinuation: pending.approvedContinuation
            )
        )
        let prompt = await promptForRequiredBrowserInput(
            requirement,
            inspection: latestInspection,
            controller: browserController
        )
        try await persistBrowserRunArtifacts(
            outcome: "awaiting_user_input",
            goalText: pending.intent.goalText,
            initialURL: pending.intent.initialURL,
            session: session,
            controller: browserController,
            inspectionHistory: inspectionHistory,
            recentHistory: recentHistory,
            finalSummary: prompt,
            scenarioMetadata: pending.scenarioMetadata
        )
        try emitAssistantMessage(prompt, session: session, shouldStore: pending.persistMessages)
        return BrowserScenarioRunSummary(
            scenarioID: pending.scenarioMetadata?.id ?? "ad_hoc",
            category: pending.scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: pending.intent.goalText, initialURL: pending.intent.initialURL),
            outcome: "awaiting_user_input",
            finalSummary: prompt
        )
    }

    private func browserInputPrompt(for requirement: BrowserPageRequirement?, inspection: ChromiumInspection?) -> String {
        if let requirement {
            switch requirement.kind {
            case "phone_number":
                if let inspection, BrowserPageAnalyzer.verificationInterruptionLikely(for: inspection) {
                    return "The site still needs a phone number before it can send the verification code."
                }
                return requirement.prompt
            case "verification_code":
                return "\(requirement.prompt) If the native macOS one-time-code suggestion appears, you can use it, or just send me the digits."
            case "consent":
                return "\(requirement.prompt) Reply with `yes` to accept it or `no` to cancel."
            default:
                return requirement.prompt
            }
        }
        if requiresVerificationCode(for: inspection) {
            return "The current browser page is waiting for a verification code. Send the digits and I’ll enter them in the active CEF page."
        }
        return "The current browser page still needs more information before it can continue. Send the missing details and I’ll keep going in the same browser session."
    }

    private func promptForRequiredBrowserInput(
        _ requirement: BrowserPageRequirement,
        inspection: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async -> String {
        _ = controller
        return browserInputPrompt(for: requirement, inspection: inspection)
    }

    private func userFacingBrowserStateMessage(
        inspection: ChromiumInspection?,
        priorInspection: ChromiumInspection? = nil,
        controller: ChromiumBrowserController
    ) async -> String? {
        guard let state = BrowserPageAnalyzer.canonicalState(for: inspection, priorInspection: priorInspection) else {
            return nil
        }

        switch state.stage {
        case .approvalBoundary:
            guard let approvalLabel = state.approvalBoundaryLabel else { return nil }
            return approvalPrompt(for: approvalLabel, inspection: inspection)
        case .detailsForm, .phoneVerificationPrep, .verificationCode:
            guard let requirement = state.promptableRequirement else { return nil }
            return await promptForRequiredBrowserInput(
                requirement,
                inspection: inspection,
                controller: controller
            )
        default:
            return BrowserPageAnalyzer.userFacingProgressMessage(for: state)
        }
    }

    private func verificationFollowUpPromptIfNeeded(
        inspection: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async -> String? {
        if let retryPrompt = verificationRetryPrompt(for: inspection) {
            return retryPrompt
        }
        guard let state = BrowserPageAnalyzer.canonicalState(for: inspection) else {
            return nil
        }
        guard state.stage == .phoneVerificationPrep || state.stage == .verificationCode else {
            return nil
        }
        if let requirement = state.promptableRequirement {
            return await promptForRequiredBrowserInput(
                requirement,
                inspection: inspection,
                controller: controller
            )
        }
        return browserInputPrompt(
            for: BrowserPageRequirement(
                id: "follow-up-verification-code",
                kind: "verification_code",
                label: "Verification code",
                selector: nil,
                controlType: "one-time-code",
                fillAction: "type_text",
                options: [],
                prompt: "I still need the verification code for this page.",
                isSensitive: true,
                priority: 145,
                validationMessage: "The current page is waiting on a verification step."
            ),
            inspection: inspection
        )
    }

    private func verificationRetryPrompt(for inspection: ChromiumInspection?) -> String? {
        guard let inspection else { return nil }

        let signals = [
            inspection.title,
            inspection.url,
            inspection.pageStage,
            inspection.notices.map(\.label).joined(separator: "\n"),
            inspection.forms.flatMap(\.fields).compactMap(\.validationMessage).joined(separator: "\n"),
            inspection.interactiveElements.compactMap(\.validationMessage).joined(separator: "\n")
        ]
        .joined(separator: "\n")
        .lowercased()

        if signals.contains("expired") || signals.contains("session expired") || signals.contains("timed out") {
            return "That verification code expired or timed out. Send a newer code and I’ll try again."
        }
        if signals.contains("invalid code")
            || signals.contains("incorrect code")
            || signals.contains("invalid verification code")
            || signals.contains("incorrect verification code")
            || signals.contains("try again") {
            return "That verification code was rejected. Send the latest code and I’ll try again."
        }

        return nil
    }

    private func requiresPhoneNumber(for inspection: ChromiumInspection?) -> Bool {
        pageRequirements(for: inspection).contains { $0.kind == "phone_number" }
    }

    private func requiresVerificationCode(for inspection: ChromiumInspection?) -> Bool {
        guard let state = BrowserPageAnalyzer.canonicalState(for: inspection) else {
            return verificationInterruptionRequirement(in: inspection) != nil
        }
        return state.stage == .verificationCode
    }

    private func isPhoneLikeField(_ field: ChromiumSemanticFormField) -> Bool {
        BrowserPageAnalyzer.requirements(for: sampleInspectionForField(field)).contains { $0.kind == "phone_number" }
    }

    private func phoneFieldPriority(_ field: ChromiumSemanticFormField) -> Int {
        switch BrowserPageAnalyzer.requirements(for: sampleInspectionForField(field)).first?.kind {
        case "phone_number": return 4
        default: return 0
        }
    }

    private func isVerificationCodeField(_ field: ChromiumSemanticFormField) -> Bool {
        BrowserPageAnalyzer.requirements(for: sampleInspectionForField(field)).contains { $0.kind == "verification_code" }
    }

    private func pageRequirements(for inspection: ChromiumInspection?) -> [BrowserPageRequirement] {
        BrowserPageAnalyzer.canonicalState(for: inspection)?.workflow.requirements
            ?? BrowserPageAnalyzer.requirements(for: inspection)
    }

    private func primaryUserRequirement(in inspection: ChromiumInspection?) -> BrowserPageRequirement? {
        if let state = BrowserPageAnalyzer.canonicalState(for: inspection),
           let promptableRequirement = state.promptableRequirement {
            return promptableRequirement
        }
        let requirements = pageRequirements(for: inspection)
        return requirements.first(where: { $0.kind != "consent" })
            ?? requirements.first
            ?? verificationInterruptionRequirement(in: inspection)
    }

    private func nextPromptableRequirement(in inspection: ChromiumInspection?) -> BrowserPageRequirement? {
        if let state = BrowserPageAnalyzer.canonicalState(for: inspection),
           let promptableRequirement = state.promptableRequirement {
            return promptableRequirement
        }
        let requirements = pageRequirements(for: inspection)
        if visibleNonVerificationRequirementExists(in: inspection) {
            return requirements.first(where: { isPromptableRequirement($0) && $0.kind != "verification_code" })
                ?? requirements.first(where: isPromptableRequirement)
        }
        return requirements.first(where: isPromptableRequirement)
            ?? verificationInterruptionRequirement(in: inspection)
    }

    private func verificationInterruptionRequirement(in inspection: ChromiumInspection?) -> BrowserPageRequirement? {
        guard let inspection else { return nil }
        guard !visibleNonVerificationRequirementExists(in: inspection) else {
            return nil
        }
        if let requirement = pageRequirements(for: inspection).first(where: { $0.kind == "verification_code" }) {
            return requirement
        }
        guard BrowserPageAnalyzer.verificationInterruptionLikely(for: inspection) else {
            return nil
        }
        return BrowserPageRequirement(
            id: "synthetic-chat-verification-interruption",
            kind: "verification_code",
            label: "Verification code",
            selector: nil,
            controlType: "one-time-code",
            fillAction: "type_text",
            options: [],
            prompt: "I still need the verification code for this page.",
            isSensitive: true,
            priority: 145,
            validationMessage: "The current page is waiting on a verification step."
        )
    }

    private func shouldPrioritizeVerificationOnly(in inspection: ChromiumInspection?) -> Bool {
        guard !visibleNonVerificationRequirementExists(in: inspection) else {
            return false
        }
        guard let state = BrowserPageAnalyzer.canonicalState(for: inspection) else {
            return verificationInterruptionRequirement(in: inspection) != nil
        }
        return state.stage == .phoneVerificationPrep || state.stage == .verificationCode
    }

    private func shouldPreserveVerificationContext(
        currentInspection: ChromiumInspection?,
        pendingInspection: ChromiumInspection?
    ) -> Bool {
        if shouldPrioritizeVerificationOnly(in: currentInspection) {
            return true
        }
        return BrowserPageAnalyzer.shouldPreserveVerificationContext(
            currentInspection: currentInspection,
            pendingInspection: pendingInspection
        )
    }

    private func visibleNonVerificationRequirementExists(in inspection: ChromiumInspection?) -> Bool {
        pageRequirements(for: inspection).contains {
            isPromptableRequirement($0) && $0.kind != "verification_code" && $0.kind != "consent"
        }
    }

    private func isPromptableRequirement(_ requirement: BrowserPageRequirement) -> Bool {
        switch requirement.kind {
        case "phone_number",
             "email",
             "full_name",
             "first_name",
             "last_name",
             "address_line1",
             "address_line2",
             "city",
             "state",
             "postal_code",
             "country",
             "verification_code",
             "consent",
             "payment_card_number",
             "payment_expiry",
             "payment_security_code":
            return true
        default:
            return false
        }
    }

    private func mergedKnownFollowUpData(
        personaID _: String,
        providedData: BrowserSessionFollowUpData?
    ) -> BrowserSessionFollowUpData? {
        if let profileData = userProfileFollowUpData() {
            return profileData.merged(with: providedData)
        }
        return providedData
    }

    private func sampleInspectionForField(_ field: ChromiumSemanticFormField) -> ChromiumInspection {
        ChromiumInspection(
            title: "Field sample",
            url: "about:blank",
            pageStage: "form",
            formCount: 1,
            hasSearchField: false,
            interactiveElements: [],
            forms: [
                ChromiumSemanticForm(
                    id: "sample-form",
                    label: "Sample",
                    selector: "form",
                    submitLabel: nil,
                    fields: [field]
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
    }

    private func applyFollowUpDataToBrowser(
        inspection: ChromiumInspection?,
        followUp: BrowserSessionFollowUpData,
        controller: ChromiumBrowserController,
        includeVerificationCode: Bool,
        forceVerificationOnly: Bool = false
    ) async throws -> (statusLines: [String], inspection: ChromiumInspection)? {
        guard !followUp.isEmpty else { return nil }

        var updatedInspection = inspection
        if updatedInspection == nil {
            updatedInspection = try? await controller.inspectCurrentPageForAgent()
        }
        guard updatedInspection != nil else { return nil }

        var statusLines: [String] = []
        var handled = false
        let verificationOnly = forceVerificationOnly || shouldPrioritizeVerificationOnly(in: updatedInspection)

        for requirement in pageRequirements(for: updatedInspection) {
            if verificationOnly {
                continue
            }
            if requirement.kind == "verification_code" {
                continue
            }
            guard let value = followUpValue(for: requirement, followUp: followUp) else { continue }
            try await applyRequirement(requirement, value: value, controller: controller)
            updatedInspection = try await controller.inspectCurrentPageForAgent()
            statusLines.append("Filled the required \(humanReadableRequirementLabel(requirement)) in the current browser page.")
            handled = true
        }

        if includeVerificationCode,
           let verificationCode = followUp.verificationCode,
           (forceVerificationOnly || shouldPrioritizeVerificationOnly(in: updatedInspection)) {
            _ = try await controller.typeVerificationCodeForAgent(verificationCode)
            updatedInspection = try await settleAndInspectAfterVerificationInput(
                controller: controller,
                fallback: try await controller.inspectCurrentPageForAgent()
            ) ?? updatedInspection
            statusLines.append("Entered the verification code in the current browser page.")
            handled = true
            if let advanced = try await advanceVerificationStepIfPossible(
                inspection: updatedInspection,
                controller: controller
            ) {
                updatedInspection = try await settleAndInspectAfterVerificationInput(
                    controller: controller,
                    fallback: advanced.inspection
                ) ?? advanced.inspection
                statusLines.append(advanced.summary)
            }
        }

        guard handled, let updatedInspection else { return nil }
        return (statusLines, updatedInspection)
    }

    private func settleAndInspectAfterVerificationInput(
        controller: ChromiumBrowserController,
        fallback: ChromiumInspection?
    ) async throws -> ChromiumInspection? {
        var latestInspection = fallback
        if latestInspection == nil {
            latestInspection = try? await controller.inspectCurrentPageForAgent()
        }

        for attempt in 0..<8 {
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 700_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            do {
                _ = try await controller.waitForSettleForAgent(timeout: 1.5)
            } catch {
                // Keep polling. Some sites auto-submit OTP and transition without a clean settle signal.
            }

            guard let refreshedInspection = try? await controller.inspectCurrentPageForAgent() else {
                continue
            }
            latestInspection = refreshedInspection

            let nextRequirement = nextPromptableRequirement(in: refreshedInspection)
            if nextRequirement?.kind != "verification_code" {
                break
            }

            if let workflow = BrowserPageAnalyzer.workflow(for: refreshedInspection),
               workflow.stage != "verification" {
                break
            }
        }

        return latestInspection
    }

    private func continueBrowserAutonomouslyUntilBlocked(
        inspection: ChromiumInspection?,
        personaID: String,
        knownData: BrowserSessionFollowUpData,
        controller: ChromiumBrowserController,
        inspectionHistory initialInspectionHistory: [ChromiumInspection],
        recentHistory initialRecentHistory: [String],
        maxCycles: Int = 6
    ) async throws -> BrowserAutonomousContinuationResult {
        var latestInspection = inspection
        var inspectionHistory = initialInspectionHistory
        var recentHistory = initialRecentHistory
        var statusLines: [String] = []

        func recordInspection(_ inspection: ChromiumInspection?) {
            guard let inspection else { return }
            inspectionHistory.append(inspection)
            if inspectionHistory.count > 20 {
                inspectionHistory.removeFirst(inspectionHistory.count - 20)
            }
        }

        for cycle in 0..<maxCycles {
            if latestInspection == nil {
                latestInspection = try? await controller.inspectCurrentPageForAgent()
                recordInspection(latestInspection)
            }

            if let autofill = try await autoFillKnownRequirementsIfPossible(
                inspection: latestInspection,
                personaID: personaID,
                providedData: knownData,
                controller: controller
            ) {
                latestInspection = autofill.inspection
                recordInspection(autofill.inspection)
                recentHistory.append("Autofill: \(autofill.summary)")
                if recentHistory.count > 6 {
                    recentHistory.removeFirst(recentHistory.count - 6)
                }
                statusLines.append(autofill.summary)
                do {
                    latestInspection = try await controller.inspectCurrentPageForAgent()
                    recordInspection(latestInspection)
                } catch {
                    latestInspection = autofill.inspection
                }
                continue
            }

            guard let requirement = nextPromptableRequirement(in: latestInspection) else {
                return BrowserAutonomousContinuationResult(
                    inspection: latestInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    statusLines: statusLines,
                    requiredInput: nil
                )
            }

            if let value = followUpValue(for: requirement, followUp: knownData),
               requirement.kind != "verification_code" {
                try await applyRequirement(requirement, value: value, controller: controller)
                latestInspection = try? await controller.inspectCurrentPageForAgent()
                recordInspection(latestInspection)
                let summary = "Filled the required \(humanReadableRequirementLabel(requirement)) in the current browser page."
                statusLines.append(summary)
                recentHistory.append(summary)
                if recentHistory.count > 6 {
                    recentHistory.removeFirst(recentHistory.count - 6)
                }
                continue
            }

            if requirement.kind == "verification_code" {
                let settledInspection = try await settleAndInspectAfterVerificationInput(
                    controller: controller,
                    fallback: latestInspection
                ) ?? latestInspection
                if cycle < maxCycles - 1,
                   let settledInspection,
                   !shouldPrioritizeVerificationOnly(in: settledInspection) {
                    latestInspection = settledInspection
                    recordInspection(settledInspection)
                    recentHistory.append("Observed the browser move past the verification step.")
                    if recentHistory.count > 6 {
                        recentHistory.removeFirst(recentHistory.count - 6)
                    }
                    continue
                }
                return BrowserAutonomousContinuationResult(
                    inspection: settledInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    statusLines: statusLines,
                    requiredInput: requirement
                )
            }

            return BrowserAutonomousContinuationResult(
                inspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                statusLines: statusLines,
                requiredInput: requirement
            )
        }

        return BrowserAutonomousContinuationResult(
            inspection: latestInspection,
            inspectionHistory: inspectionHistory,
            recentHistory: recentHistory,
            statusLines: statusLines,
            requiredInput: nextPromptableRequirement(in: latestInspection)
        )
    }

    private func advanceVerificationStepIfPossible(
        inspection: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async throws -> (summary: String, inspection: ChromiumInspection)? {
        guard let inspection, shouldPrioritizeVerificationOnly(in: inspection) else {
            return nil
        }

        if let advanced = try? await controller.advanceVerificationStepForAgent() {
            let refreshedInspection = try await controller.inspectCurrentPageForAgent()
            return ("Advanced the verification step (\(advanced)).", refreshedInspection)
        }

        let candidate = inspection.semanticTargets
            .filter { target in
                ["dialog_action", "primary_action", "action"].contains(target.kind)
                    && !target.selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .filter { target in
                let label = target.label.lowercased()
                if label.contains("use email instead")
                    || label.contains("use phone instead")
                    || label.contains("sign in")
                    || label.contains("log in")
                    || label.contains("login")
                    || label.contains("close")
                    || label.contains("dismiss") {
                    return false
                }
                if let purpose = target.purpose, ["continue", "confirm"].contains(purpose) {
                    return true
                }
                return label.contains("continue")
                    || label.contains("verify")
                    || label.contains("submit")
                    || label.contains("done")
                    || label.contains("next")
            }
            .sorted { lhs, rhs in lhs.priority > rhs.priority }
            .first

        if let candidate {
            _ = try await controller.clickSelectorForAgent(
                candidate.selector,
                label: candidate.label,
                transactionalKind: candidate.transactionalKind,
                requireApproval: false
            )
            let refreshedInspection = try await controller.inspectCurrentPageForAgent()
            return ("Advanced the verification step with \(candidate.label).", refreshedInspection)
        }

        _ = try await controller.pressKeyForAgent("Enter")
        let refreshedInspection = try await controller.inspectCurrentPageForAgent()
        return ("Attempted to advance the verification step with Enter.", refreshedInspection)
    }

    private func followUpValue(for requirement: BrowserPageRequirement, followUp: BrowserSessionFollowUpData) -> String? {
        switch requirement.kind {
        case "phone_number":
            return followUp.phoneNumber
        case "email":
            return followUp.email
        case "full_name":
            return followUp.fullName
        case "first_name":
            return followUp.firstName ?? splitFullName(followUp.fullName)?.firstName
        case "last_name":
            return followUp.lastName ?? splitFullName(followUp.fullName)?.lastName
        case "address_line1":
            return followUp.addressLine1
        case "address_line2":
            return followUp.addressLine2
        case "city":
            return followUp.city
        case "state":
            return followUp.state
        case "postal_code":
            return followUp.postalCode
        case "country":
            return followUp.country
        case "verification_code":
            return followUp.verificationCode
        case "consent":
            guard let decision = followUp.consentDecision else { return nil }
            return decision ? "true" : "false"
        default:
            return nil
        }
    }

    private func userProfileFollowUpData() -> BrowserSessionFollowUpData? {
        guard let profile = userProfileManager.loadContactProfile() else { return nil }
        let fullName = profile.fullName ?? [profile.firstName, profile.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return BrowserSessionFollowUpData(
            phoneNumber: profile.phoneNumber,
            email: profile.email,
            fullName: fullName.isEmpty ? nil : fullName,
            firstName: profile.firstName,
            lastName: profile.lastName,
            addressLine1: profile.addressLine1,
            addressLine2: profile.addressLine2,
            city: profile.city,
            state: profile.state,
            postalCode: profile.postalCode,
            country: profile.country,
            verificationCode: nil,
            consentDecision: nil
        )
    }

    private func autoFillKnownRequirementsIfPossible(
        inspection: ChromiumInspection?,
        personaID: String,
        providedData: BrowserSessionFollowUpData?,
        controller: ChromiumBrowserController
    ) async throws -> (summary: String, inspection: ChromiumInspection)? {
        guard let inspection,
              let knownData = mergedKnownFollowUpData(personaID: personaID, providedData: providedData),
              !shouldPrioritizeVerificationOnly(in: inspection) else {
            return nil
        }

        let eligibleRequirements = pageRequirements(for: inspection).filter {
            $0.kind != "verification_code" && $0.kind != "consent"
        }
        guard !eligibleRequirements.isEmpty else { return nil }

        var filledLabels: [String] = []
        for requirement in eligibleRequirements {
            guard let value = followUpValue(for: requirement, followUp: knownData) else { continue }
            try await applyRequirement(requirement, value: value, controller: controller)
            filledLabels.append(humanReadableRequirementLabel(requirement))
        }

        guard !filledLabels.isEmpty else { return nil }
        let refreshedInspection = try await controller.inspectCurrentPageForAgent()
        let uniqueLabels = Array(NSOrderedSet(array: filledLabels)) as? [String] ?? filledLabels
        let summary = "Filled known profile data for the current page: \(uniqueLabels.joined(separator: ", "))."
        return (summary, refreshedInspection)
    }

    private func applyRequirement(
        _ requirement: BrowserPageRequirement,
        value: String,
        controller: ChromiumBrowserController
    ) async throws {
        guard let selector = requirement.selector else {
            throw ChromiumBrowserActionError(message: "Missing selector for required field \(requirement.label).")
        }
        switch requirement.fillAction {
        case "click":
            if value == "false" {
                return
            }
            _ = try await controller.clickSelectorForAgent(selector, label: requirement.label, requireApproval: false)
        case "select_option":
            _ = try await controller.selectOptionForAgent(value, selector: selector)
        default:
            _ = try await controller.typeTextForAgent(value, selector: selector)
        }
    }

    private func humanReadableRequirementLabel(_ requirement: BrowserPageRequirement) -> String {
        switch requirement.kind {
        case "phone_number": return "phone number"
        case "email": return "email address"
        case "full_name": return "full name"
        case "first_name": return "first name"
        case "last_name": return "last name"
        case "address_line1": return "street address"
        case "address_line2": return "apartment or unit details"
        case "postal_code": return "postal code"
        case "verification_code": return "verification code"
        default:
            return requirement.label
        }
    }

    private func splitFullName(_ fullName: String?) -> (firstName: String, lastName: String)? {
        guard let fullName else { return nil }
        let parts = fullName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return (parts.first ?? "", parts.dropFirst().joined(separator: " "))
    }

    private func messageMentionsVerificationCode(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("verification code")
            || normalized.contains("verification")
            || normalized.contains("otp")
            || normalized.contains("passcode")
            || normalized.contains("security code")
            || normalized.contains("one time code")
            || normalized.contains("one-time code")
    }

    private func executePendingApprovedBrowserCommand(
        _ command: BrowserAgentCommand,
        intent: GenericBrowserChatIntent,
        inspection: ChromiumInspection?,
        controller: ChromiumBrowserController
    ) async throws -> BrowserAgentExecutionResult {
        do {
            return try await executeBrowserAgentCommand(
                command,
                inspection: inspection,
                goalFocusTerms: intent.goalFocusTerms,
                controller: controller,
                requireApproval: false
            )
        } catch {
            let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
            guard isRecoverableBrowserError(message) else {
                throw error
            }
            let refreshedInspection = try await controller.inspectCurrentPageForAgent()
            if let recoveredExecution = try await retryBrowserAgentCommandIfPossible(
                command,
                staleInspection: inspection,
                refreshedInspection: refreshedInspection,
                goalFocusTerms: intent.goalFocusTerms,
                controller: controller,
                requireApproval: false
            ) {
                return recoveredExecution
            }
            throw ChromiumBrowserActionError(message: message)
        }
    }

    private func pendingBrowserApprovalContext(for sessionID: UUID) -> PendingBrowserApprovalContext? {
        pendingApprovalLock.lock()
        defer { pendingApprovalLock.unlock() }
        guard let pendingBrowserApproval, pendingBrowserApproval.sessionID == sessionID else {
            return nil
        }
        return pendingBrowserApproval
    }

    private func setPendingBrowserApproval(_ pending: PendingBrowserApprovalContext) {
        pendingApprovalLock.lock()
        pendingBrowserApproval = pending
        pendingApprovalLock.unlock()
    }

    private func clearPendingBrowserApproval(for sessionID: UUID) {
        pendingApprovalLock.lock()
        if pendingBrowserApproval?.sessionID == sessionID {
            pendingBrowserApproval = nil
        }
        pendingApprovalLock.unlock()
    }

    private func pendingBrowserInputContext(for sessionID: UUID) -> PendingBrowserInputContext? {
        pendingInputLock.lock()
        defer { pendingInputLock.unlock() }
        guard let pendingBrowserInput, pendingBrowserInput.sessionID == sessionID else {
            return nil
        }
        return pendingBrowserInput
    }

    private func setPendingBrowserInput(_ pending: PendingBrowserInputContext) {
        pendingInputLock.lock()
        pendingBrowserInput = pending
        pendingInputLock.unlock()
        configurePendingBrowserInputMonitor(for: pending)
    }

    private func clearPendingBrowserInput(for sessionID: UUID) {
        var cleared = false
        pendingInputLock.lock()
        if pendingBrowserInput?.sessionID == sessionID {
            pendingBrowserInput = nil
            cleared = true
        }
        pendingInputLock.unlock()
        if cleared {
            cancelPendingBrowserInputMonitor()
        }
    }

    private func configurePendingBrowserInputMonitor(for pending: PendingBrowserInputContext) {
        cancelPendingBrowserInputMonitor()
        guard shouldPrioritizeVerificationOnly(in: pending.latestInspection) else {
            return
        }

        pendingInputMonitorLock.lock()
        pendingBrowserInputMonitor = Task { [weak self] in
            guard let self else { return }
            await self.monitorPendingVerificationTransition(for: pending.sessionID)
        }
        pendingInputMonitorLock.unlock()
    }

    private func cancelPendingBrowserInputMonitor() {
        pendingInputMonitorLock.lock()
        pendingBrowserInputMonitor?.cancel()
        pendingBrowserInputMonitor = nil
        pendingInputMonitorLock.unlock()
    }

    private func monitorPendingVerificationTransition(for sessionID: UUID) async {
        guard let pending = pendingBrowserInputContext(for: sessionID) else {
            return
        }

        let browserController = await MainActor.run { browserControllerProvider() }
        var latestInspection = pending.latestInspection
        for _ in 0..<6 {
            guard !Task.isCancelled else { return }
            guard let currentPending = pendingBrowserInputContext(for: sessionID),
                  currentPending.personaID == pending.personaID else {
                return
            }

            let settledInspection = try? await settleAndInspectAfterVerificationInput(
                controller: browserController,
                fallback: latestInspection
            )
            latestInspection = settledInspection ?? latestInspection
            if let transitionedInspection = latestInspection,
               !shouldPrioritizeVerificationOnly(in: transitionedInspection) {
                try? await resumePendingBrowserInputAfterVerificationAdvance(
                    currentPending,
                    transitionedInspection: transitionedInspection,
                    controller: browserController
                )
                return
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func resumePendingBrowserInputAfterVerificationAdvance(
        _ pending: PendingBrowserInputContext,
        transitionedInspection: ChromiumInspection,
        controller browserController: ChromiumBrowserController
    ) async throws {
        var latestInspection: ChromiumInspection? = transitionedInspection
        var inspectionHistory = pending.inspectionHistory
        var recentHistory = pending.recentHistory
        let knownData = pending.knownFollowUpData

        inspectionHistory.append(transitionedInspection)
        if inspectionHistory.count > 20 {
            inspectionHistory.removeFirst(inspectionHistory.count - 20)
        }
        recentHistory.append("Detected that the verification step advanced in the active browser page.")
        if recentHistory.count > 6 {
            recentHistory.removeFirst(recentHistory.count - 6)
        }

        let continuation = try await continueBrowserAutonomouslyUntilBlocked(
            inspection: latestInspection,
            personaID: pending.personaID,
            knownData: knownData,
            controller: browserController,
            inspectionHistory: inspectionHistory,
            recentHistory: recentHistory
        )
        latestInspection = continuation.inspection
        inspectionHistory = continuation.inspectionHistory
        recentHistory = continuation.recentHistory

        if !continuation.statusLines.isEmpty,
           let message = await userFacingBrowserStateMessage(
                inspection: latestInspection,
                controller: browserController
           ) {
            let session = try sessionStore.loadOrCreateDefault(personaId: pending.personaID)
            try emitAssistantMessage(message, session: session, shouldStore: pending.persistMessages)
        }

        if let requirement = continuation.requiredInput,
           followUpValue(for: requirement, followUp: knownData) == nil {
            let prompt = await promptForRequiredBrowserInput(
                requirement,
                inspection: latestInspection,
                controller: browserController
            )
            setPendingBrowserInput(
                PendingBrowserInputContext(
                    sessionID: pending.sessionID,
                    personaID: pending.personaID,
                    intent: pending.intent,
                    latestInspection: latestInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    persistMessages: pending.persistMessages,
                    scenarioMetadata: pending.scenarioMetadata,
                    knownFollowUpData: knownData,
                    approvedContinuation: pending.approvedContinuation
                )
            )
            let session = try sessionStore.loadOrCreateDefault(personaId: pending.personaID)
            try emitAssistantMessage(prompt, session: session, shouldStore: pending.persistMessages)
            return
        }

        clearPendingBrowserInput(for: pending.sessionID)

        guard let approvedContinuation = pending.approvedContinuation else {
            return
        }

        let persona = try personaManager.validatePersona(personaId: pending.personaID)
        var session = try sessionStore.loadOrCreateDefault(personaId: pending.personaID)
        let runtimeConfig = try runtimeConfigStore.loadOrCreateDefault()
        let launchConfig = CodexLaunchConfig(
            agentHomeDirectory: persona.directoryPath,
            codexHome: paths.root.path,
            runtimeMode: .chatOnly,
            externalDirectory: nil,
            enableSearch: false,
            model: runtimeConfig.model,
            reasoningEffort: runtimeConfig.reasoningEffort
        )

        _ = try await runGenericBrowserLoop(
            GenericBrowserChatIntent(
                goalText: pending.intent.goalText,
                initialURL: pending.intent.initialURL,
                goalFocusTerms: pending.intent.goalFocusTerms,
                providedData: knownData
            ),
            session: &session,
            controller: browserController,
            launchConfig: launchConfig,
            persistMessages: pending.persistMessages,
            scenarioMetadata: pending.scenarioMetadata,
            seed: BrowserLoopSeed(
                latestInspection: latestInspection,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                lastResultSummary: recentHistory.last ?? "The verification step advanced and the browser flow resumed."
            ),
            approvedContinuation: approvedContinuation
        )
        try sessionStore.save(session)
    }

    private func runGenericBrowserLoop(
        _ intent: GenericBrowserChatIntent,
        session: inout AssistantSession,
        controller browserController: ChromiumBrowserController,
        launchConfig: CodexLaunchConfig,
        persistMessages: Bool,
        scenarioMetadata: BrowserScenarioMetadata?,
        seed: BrowserLoopSeed,
        approvedContinuation: BrowserApprovedContinuationContext? = nil
    ) async throws -> BrowserScenarioRunSummary {
        var lastResultSummary = seed.lastResultSummary
        var latestInspection = seed.latestInspection
        var inspectionHistory = seed.inspectionHistory
        var recentHistory = seed.recentHistory
        var actionSignatureCounts: [String: Int] = [:]
        var lastProgressSnapshot: BrowserProgressSnapshot?
        var stalledStepCount = 0
        var recoveryCount = 0
        let maxSteps = isTransactionalBrowserGoal(intent.goalText) ? 18 : 12

        func recordInspection(_ inspection: ChromiumInspection?) {
            guard let inspection else { return }
            inspectionHistory.append(inspection)
            if inspectionHistory.count > 20 {
                inspectionHistory.removeFirst(inspectionHistory.count - 20)
            }
        }

        do {
            for step in 1...maxSteps {
                if let autofill = try await autoFillKnownRequirementsIfPossible(
                    inspection: latestInspection,
                    personaID: session.personaId,
                    providedData: intent.providedData,
                    controller: browserController
                ) {
                    latestInspection = autofill.inspection
                    recordInspection(autofill.inspection)
                    lastResultSummary = autofill.summary
                    recentHistory.append("Autofill: \(autofill.summary)")
                    if recentHistory.count > 6 {
                        recentHistory.removeFirst(recentHistory.count - 6)
                    }
                }

                if scenarioMetadata == nil,
                   let requirement = nextPromptableRequirement(in: latestInspection),
                   followUpValue(
                        for: requirement,
                        followUp: mergedKnownFollowUpData(personaID: session.personaId, providedData: intent.providedData)
                            ?? .empty
                    ) == nil {
                    let finalText = await promptForRequiredBrowserInput(
                        requirement,
                        inspection: latestInspection,
                        controller: browserController
                    )
                    setPendingBrowserInput(
                        PendingBrowserInputContext(
                            sessionID: session.id,
                            personaID: session.personaId,
                            intent: intent,
                            latestInspection: latestInspection,
                            inspectionHistory: inspectionHistory,
                            recentHistory: recentHistory,
                            persistMessages: persistMessages,
                            scenarioMetadata: scenarioMetadata,
                            knownFollowUpData: mergedKnownFollowUpData(personaID: session.personaId, providedData: intent.providedData)
                                ?? .empty,
                            approvedContinuation: approvedContinuation
                        )
                    )
                    try await persistBrowserRunArtifacts(
                        outcome: "awaiting_user_input",
                        goalText: intent.goalText,
                        initialURL: intent.initialURL,
                        session: session,
                        controller: browserController,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        finalSummary: finalText,
                        scenarioMetadata: scenarioMetadata
                    )
                    try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                    return BrowserScenarioRunSummary(
                        scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                        category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                        outcome: "awaiting_user_input",
                        finalSummary: finalText
                    )
                }

                let state = await MainActor.run { browserController.browserSnapshot() }
                let prompt = buildBrowserAgentPrompt(
                    goalText: intent.goalText,
                    goalFocusTerms: intent.goalFocusTerms,
                    initialURL: intent.initialURL,
                    state: state,
                    inspection: latestInspection,
                    lastResultSummary: lastResultSummary,
                    recentHistory: recentHistory,
                    step: step,
                    maxSteps: maxSteps
                )

                let turn = try await performCodexTurn(
                    prompt: prompt,
                    session: &session,
                    config: launchConfig,
                    forwardAssistantLines: false
                )

                if turn.result.exitCode != 0 {
                    let message = turn.stderrText.isEmpty
                        ? "Browser agent turn failed with exit code \(turn.result.exitCode)"
                        : turn.stderrText
                    throw ChromiumBrowserActionError(message: message)
                }

                let parsed = parseBrowserAssistantResponse(turn.assistantText)

                guard let command = parsed.command else {
                    throw ChromiumBrowserActionError(message: "Codex did not return a browser command.")
                }

                let signature = browserActionSignature(command, url: state.urlString)
                actionSignatureCounts[signature, default: 0] += 1
                if actionSignatureCounts[signature, default: 0] >= 3 {
                    let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
                    latestInspection = refreshedInspection
                    recordInspection(refreshedInspection)
                    lastResultSummary = browserRecoverySummary(
                        for: command,
                        message: "The same action repeated without changing the page.",
                        inspection: refreshedInspection,
                        progressChanged: false
                    )
                    recentHistory.append("Recovery: repeated \(command.action.rawValue) without progress.")
                    if recentHistory.count > 6 {
                        recentHistory.removeFirst(recentHistory.count - 6)
                    }
                    actionSignatureCounts[signature] = 0
                    stalledStepCount = 0
                    recoveryCount += 1
                    if recoveryCount >= 4 {
                        throw ChromiumBrowserActionError(message: "Browser agent is stuck on stale targets and repeated replans.")
                    }
                    continue
                }

                if command.action == .done {
                    if let reason = incompleteBrowserGoalReason(goalText: intent.goalText, inspection: latestInspection) {
                        lastResultSummary = reason
                        recentHistory.append("Recovery: done -> \(reason)")
                        if recentHistory.count > 6 {
                            recentHistory.removeFirst(recentHistory.count - 6)
                        }
                        stalledStepCount = 0
                        recoveryCount += 1
                        if recoveryCount >= 4 {
                            throw ChromiumBrowserActionError(message: "Browser agent attempted to stop repeatedly before completing the visible booking flow.")
                        }
                        continue
                    }

                    if let approvalCommand = pendingApprovalCommand(from: latestInspection),
                       let approvalLabel = approvalBoundaryLabelIfNeeded(for: approvalCommand, inspection: latestInspection),
                       !BrowserApprovedContinuationGuard.matches(
                            approvedContinuation,
                            command: approvalCommand,
                            inspection: latestInspection
                       ) {
                        if scenarioMetadata != nil {
                            let finalText = "Stopped before the final confirmation boundary at \"\(approvalLabel)\". Approval is still required for any final transaction step."
                            try await persistBrowserRunArtifacts(
                                outcome: "stopped_at_confirmation_boundary",
                                goalText: intent.goalText,
                                initialURL: intent.initialURL,
                                session: session,
                                controller: browserController,
                                inspectionHistory: inspectionHistory,
                                recentHistory: recentHistory,
                                finalSummary: finalText,
                                scenarioMetadata: scenarioMetadata
                            )
                            try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                            return BrowserScenarioRunSummary(
                                scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                                category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                                outcome: "stopped_at_confirmation_boundary",
                                finalSummary: finalText
                            )
                        }

                        let finalText = approvalPrompt(for: approvalLabel, inspection: latestInspection)
                        setPendingBrowserApproval(
                            PendingBrowserApprovalContext(
                                sessionID: session.id,
                                intent: intent,
                                command: approvalCommand,
                                approvalLabel: approvalLabel,
                                latestInspection: latestInspection,
                                inspectionHistory: inspectionHistory,
                                recentHistory: recentHistory,
                                persistMessages: persistMessages
                            )
                        )
                        try await persistBrowserRunArtifacts(
                            outcome: "awaiting_user_approval",
                            goalText: intent.goalText,
                            initialURL: intent.initialURL,
                            session: session,
                            controller: browserController,
                            inspectionHistory: inspectionHistory,
                            recentHistory: recentHistory,
                            finalSummary: finalText,
                            scenarioMetadata: scenarioMetadata
                        )
                        try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                        return BrowserScenarioRunSummary(
                            scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                            category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                            outcome: "awaiting_user_approval",
                            finalSummary: finalText
                        )
                    }

                    let finalText = parsed.displayText.isEmpty
                        ? (command.finalResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Finished the browser task.")
                        : parsed.displayText
                    try await persistBrowserRunArtifacts(
                        outcome: "completed",
                        goalText: intent.goalText,
                        initialURL: intent.initialURL,
                        session: session,
                        controller: browserController,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        finalSummary: finalText,
                        scenarioMetadata: scenarioMetadata
                    )
                    try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                    return BrowserScenarioRunSummary(
                        scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                        category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                        outcome: "completed",
                        finalSummary: finalText
                    )
                }

                let isApprovedContinuationCommand = BrowserApprovedContinuationGuard.matches(
                    approvedContinuation,
                    command: command,
                    inspection: latestInspection
                )

                if let approvalBoundaryLabel = approvalBoundaryLabelIfNeeded(for: command, inspection: latestInspection),
                   !isApprovedContinuationCommand {
                    if scenarioMetadata != nil {
                        let finalText = "Stopped before the final confirmation boundary at \"\(approvalBoundaryLabel)\". Approval is still required for any final transaction step."
                        try await persistBrowserRunArtifacts(
                            outcome: "stopped_at_confirmation_boundary",
                            goalText: intent.goalText,
                            initialURL: intent.initialURL,
                            session: session,
                            controller: browserController,
                            inspectionHistory: inspectionHistory,
                            recentHistory: recentHistory,
                            finalSummary: finalText,
                            scenarioMetadata: scenarioMetadata
                        )
                        try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                        return BrowserScenarioRunSummary(
                            scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                            category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                            outcome: "stopped_at_confirmation_boundary",
                            finalSummary: finalText
                        )
                    }

                    let finalText = approvalPrompt(for: approvalBoundaryLabel, inspection: latestInspection)
                    setPendingBrowserApproval(
                        PendingBrowserApprovalContext(
                            sessionID: session.id,
                            intent: intent,
                            command: command,
                            approvalLabel: approvalBoundaryLabel,
                            latestInspection: latestInspection,
                            inspectionHistory: inspectionHistory,
                            recentHistory: recentHistory,
                            persistMessages: persistMessages
                        )
                    )
                    try await persistBrowserRunArtifacts(
                        outcome: "awaiting_user_approval",
                        goalText: intent.goalText,
                        initialURL: intent.initialURL,
                        session: session,
                        controller: browserController,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        finalSummary: finalText,
                        scenarioMetadata: scenarioMetadata
                    )
                    try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                    return BrowserScenarioRunSummary(
                        scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                        category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                        outcome: "awaiting_user_approval",
                        finalSummary: finalText
                    )
                }

                let previousProgressSnapshot = browserProgressSnapshot(state: state, inspection: latestInspection)
                let execution: BrowserAgentExecutionResult
                do {
                    execution = try await executeBrowserAgentCommand(
                        command,
                        inspection: latestInspection,
                        goalFocusTerms: intent.goalFocusTerms,
                        controller: browserController,
                        requireApproval: !isApprovedContinuationCommand
                    )
                } catch {
                    let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
                    guard isRecoverableBrowserError(message) else {
                        throw error
                    }
                    let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
                    recordInspection(refreshedInspection)
                    if let recoveredExecution = try await retryBrowserAgentCommandIfPossible(
                        command,
                        staleInspection: latestInspection,
                        refreshedInspection: refreshedInspection,
                        goalFocusTerms: intent.goalFocusTerms,
                        controller: browserController,
                        requireApproval: !isApprovedContinuationCommand
                    ) {
                        latestInspection = recoveredExecution.inspection ?? refreshedInspection
                        recordInspection(latestInspection)
                        lastResultSummary = recoveredExecution.summary
                        recentHistory.append("Recovery: \(command.action.rawValue) -> \(recoveredExecution.summary)")
                        if recentHistory.count > 6 {
                            recentHistory.removeFirst(recentHistory.count - 6)
                        }
                        let recoveredState = await MainActor.run { browserController.browserSnapshot() }
                        lastProgressSnapshot = browserProgressSnapshot(state: recoveredState, inspection: latestInspection)
                        stalledStepCount = 0
                        recoveryCount += 1
                        continue
                    }
                    latestInspection = refreshedInspection
                    let currentState = await MainActor.run { browserController.browserSnapshot() }
                    let refreshedProgressSnapshot = browserProgressSnapshot(state: currentState, inspection: refreshedInspection)
                    lastResultSummary = browserRecoverySummary(
                        for: command,
                        message: message,
                        inspection: refreshedInspection,
                        progressChanged: refreshedProgressSnapshot != previousProgressSnapshot
                    )
                    recentHistory.append("Recovery: \(command.action.rawValue) -> \(message)")
                    if recentHistory.count > 6 {
                        recentHistory.removeFirst(recentHistory.count - 6)
                    }
                    stalledStepCount = 0
                    recoveryCount += 1
                    if recoveryCount >= 4 {
                        throw ChromiumBrowserActionError(message: "Browser agent exceeded the recovery budget while trying to re-target the page.")
                    }
                    continue
                }

                latestInspection = execution.inspection ?? latestInspection
                recordInspection(latestInspection)
                lastResultSummary = execution.summary
                recentHistory.append("Step \(step): \(command.action.rawValue) -> \(execution.summary)")
                if recentHistory.count > 6 {
                    recentHistory.removeFirst(recentHistory.count - 6)
                }

                if let stopReason = BrowserTransactionalGuard.stopReason(goalText: intent.goalText, inspection: latestInspection) {
                    let approvedBoundaryCommand = pendingApprovalCommand(from: latestInspection)
                    if BrowserApprovedContinuationGuard.matches(
                        approvedContinuation,
                        command: approvedBoundaryCommand,
                        inspection: latestInspection
                    ) {
                        recentHistory.append("Continuing the already-approved final step while the page advances.")
                        if recentHistory.count > 6 {
                            recentHistory.removeFirst(recentHistory.count - 6)
                        }
                        continue
                    }
                    if scenarioMetadata == nil,
                       let approvalCommand = pendingApprovalCommand(from: latestInspection),
                       let approvalLabel = approvalBoundaryLabelIfNeeded(for: approvalCommand, inspection: latestInspection) {
                        let finalText = approvalPrompt(for: approvalLabel, inspection: latestInspection)
                        setPendingBrowserApproval(
                            PendingBrowserApprovalContext(
                                sessionID: session.id,
                                intent: intent,
                                command: approvalCommand,
                                approvalLabel: approvalLabel,
                                latestInspection: latestInspection,
                                inspectionHistory: inspectionHistory,
                                recentHistory: recentHistory,
                                persistMessages: persistMessages
                            )
                        )
                        try await persistBrowserRunArtifacts(
                            outcome: "awaiting_user_approval",
                            goalText: intent.goalText,
                            initialURL: intent.initialURL,
                            session: session,
                            controller: browserController,
                            inspectionHistory: inspectionHistory,
                            recentHistory: recentHistory,
                            finalSummary: finalText,
                            scenarioMetadata: scenarioMetadata
                        )
                        try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                        return BrowserScenarioRunSummary(
                            scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                            category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                            outcome: "awaiting_user_approval",
                            finalSummary: finalText
                        )
                    }
                    let finalText = "\(stopReason) Approval is still required for any final transaction step."
                    try await persistBrowserRunArtifacts(
                        outcome: "stopped_at_confirmation_boundary",
                        goalText: intent.goalText,
                        initialURL: intent.initialURL,
                        session: session,
                        controller: browserController,
                        inspectionHistory: inspectionHistory,
                        recentHistory: recentHistory,
                        finalSummary: finalText,
                        scenarioMetadata: scenarioMetadata
                    )
                    try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                    return BrowserScenarioRunSummary(
                        scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                        category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                        outcome: "stopped_at_confirmation_boundary",
                        finalSummary: finalText
                    )
                }

                let currentState = await MainActor.run { browserController.browserSnapshot() }
                let progressSnapshot = browserProgressSnapshot(state: currentState, inspection: latestInspection)
                if progressSnapshot == lastProgressSnapshot && command.action != .inspectPage {
                    stalledStepCount += 1
                } else {
                    stalledStepCount = 0
                    recoveryCount = 0
                }
                lastProgressSnapshot = progressSnapshot

                if stalledStepCount >= 2 {
                    let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
                    latestInspection = refreshedInspection
                    recordInspection(refreshedInspection)
                    lastResultSummary = browserRecoverySummary(
                        for: command,
                        message: "The last actions did not visibly change the page state.",
                        inspection: refreshedInspection,
                        progressChanged: false
                    )
                    recentHistory.append("Recovery: refreshed inspection after stalled browser progress.")
                    if recentHistory.count > 6 {
                        recentHistory.removeFirst(recentHistory.count - 6)
                    }
                    stalledStepCount = 0
                    recoveryCount += 1
                    if recoveryCount >= 4 {
                        throw ChromiumBrowserActionError(message: "Browser agent exceeded the recovery budget after repeated stalled steps.")
                    }
                }
            }

            if let finalSummary = try await finalizeBrowserLoopAfterStepLimit(
                intent: intent,
                session: &session,
                controller: browserController,
                persistMessages: persistMessages,
                scenarioMetadata: scenarioMetadata,
                latestInspection: &latestInspection,
                inspectionHistory: &inspectionHistory,
                recentHistory: &recentHistory,
                approvedContinuation: approvedContinuation
            ) {
                return finalSummary
            }

            throw ChromiumBrowserActionError(message: "Browser agent loop exceeded the maximum number of steps.")
        } catch {
            let message = (error as? ChromiumBrowserActionError)?.message ?? error.localizedDescription
            try await persistBrowserRunArtifacts(
                outcome: "failed",
                goalText: intent.goalText,
                initialURL: intent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: message,
                scenarioMetadata: scenarioMetadata
            )
            emit(.failed(message))
            throw error
        }
    }

    private func finalizeBrowserLoopAfterStepLimit(
        intent: GenericBrowserChatIntent,
        session: inout AssistantSession,
        controller browserController: ChromiumBrowserController,
        persistMessages: Bool,
        scenarioMetadata: BrowserScenarioMetadata?,
        latestInspection: inout ChromiumInspection?,
        inspectionHistory: inout [ChromiumInspection],
        recentHistory: inout [String],
        approvedContinuation: BrowserApprovedContinuationContext?
    ) async throws -> BrowserScenarioRunSummary? {
        do {
            try await browserController.settlePageForAgent(timeout: 4)
        } catch {
            // Continue to a final inspection even if settle times out.
        }

        let refreshedInspection = try await browserController.inspectCurrentPageForAgent()
        latestInspection = refreshedInspection
        inspectionHistory.append(refreshedInspection)
        if inspectionHistory.count > 20 {
            inspectionHistory.removeFirst(inspectionHistory.count - 20)
        }
        recentHistory.append("Recovery: final inspection after step budget exhaustion.")
        if recentHistory.count > 6 {
            recentHistory.removeFirst(recentHistory.count - 6)
        }

        if let approvalCommand = pendingApprovalCommand(from: refreshedInspection),
           let approvalLabel = approvalBoundaryLabelIfNeeded(for: approvalCommand, inspection: refreshedInspection),
           !BrowserApprovedContinuationGuard.matches(
                approvedContinuation,
                command: approvalCommand,
                inspection: refreshedInspection
           ) {
            if scenarioMetadata != nil {
                let finalText = "Stopped before the final confirmation boundary at \"\(approvalLabel)\". Approval is still required for any final transaction step."
                try await persistBrowserRunArtifacts(
                    outcome: "stopped_at_confirmation_boundary",
                    goalText: intent.goalText,
                    initialURL: intent.initialURL,
                    session: session,
                    controller: browserController,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    finalSummary: finalText,
                    scenarioMetadata: scenarioMetadata
                )
                try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
                return BrowserScenarioRunSummary(
                    scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                    category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                    outcome: "stopped_at_confirmation_boundary",
                    finalSummary: finalText
                )
            }

            let finalText = approvalPrompt(for: approvalLabel, inspection: refreshedInspection)
            setPendingBrowserApproval(
                PendingBrowserApprovalContext(
                    sessionID: session.id,
                    intent: intent,
                    command: approvalCommand,
                    approvalLabel: approvalLabel,
                    latestInspection: refreshedInspection,
                    inspectionHistory: inspectionHistory,
                    recentHistory: recentHistory,
                    persistMessages: persistMessages
                )
            )
            try await persistBrowserRunArtifacts(
                outcome: "awaiting_user_approval",
                goalText: intent.goalText,
                initialURL: intent.initialURL,
                session: session,
                controller: browserController,
                inspectionHistory: inspectionHistory,
                recentHistory: recentHistory,
                finalSummary: finalText,
                scenarioMetadata: scenarioMetadata
            )
            try persistAssistantMessage(finalText, session: session, shouldStore: persistMessages)
            return BrowserScenarioRunSummary(
                scenarioID: scenarioMetadata?.id ?? "ad_hoc",
                category: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: intent.goalText, initialURL: intent.initialURL),
                outcome: "awaiting_user_approval",
                finalSummary: finalText
            )
        }

        return nil
    }

    private func buildBrowserAgentPrompt(
        goalText: String,
        goalFocusTerms: [String],
        initialURL: String?,
        state: ChromiumBrowserState,
        inspection: ChromiumInspection?,
        lastResultSummary: String,
        recentHistory: [String],
        step: Int,
        maxSteps: Int
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stateJSON = (try? encoder.encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let inspectionJSON = inspection.map(encodeJSON(_:)) ?? "null"
        let initialURLLine = initialURL.map { "Initial URL hint: \($0)" } ?? "Initial URL hint: none"
        let focusSection = goalFocusTerms.isEmpty
            ? "Goal focus hints: none"
            : "Goal focus hints:\n- " + goalFocusTerms.joined(separator: "\n- ")
        let bookingGuidanceSection = browserBookingGuidanceSection(goalText: goalText, inspection: inspection)
        let historySection = recentHistory.isEmpty
            ? "Recent browser history:\n- none yet"
            : "Recent browser history:\n- " + recentHistory.joined(separator: "\n- ")

        return """
        You are controlling an embedded Chromium browser inside AgentHub.

        Goal:
        \(goalText)

        \(focusSection)

        \(bookingGuidanceSection)

        Step \(step) of \(maxSteps)
        \(initialURLLine)

        Last browser result:
        \(lastResultSummary)

        \(historySection)

        Current browser state JSON:
        \(stateJSON)

        Latest page inspection JSON:
        \(inspectionJSON)

        Rules:
        - Choose exactly one next browser action.
        - Prefer semantic structures from the inspection JSON first:
          - semanticTargets
          - forms
          - controlGroups
          - autocompleteSurfaces
          - datePickers
          - notices
          - stepIndicators
          - resultLists
          - cards
          - dialogs
          - transactionalBoundaries
        - Use selectors from the inspection JSON when needed, but do not rely on raw selectors if a semantic target is available.
        - When you use a raw selector action, also include label when you know the semantic target so runtime recovery has a stable target name.
        - If you do not have enough page information, use inspect_page.
        - For booking, reservation, checkout, hotel, or flight goals, prefer reaching the exact item, venue, or detail page before adjusting date, time, guest, passenger, or room parameters, unless the current page clearly already represents that exact item.
        - If the goal names a specific venue, property, product, or flight, do not spend steps adjusting date, time, guest, passenger, or room controls on broad search or results pages. Use autocomplete, result-card, or search-submit actions to open the exact detail page first.
        - If goal focus hints are present, do not open a result card, detail page, or autocomplete option unless it substantially matches those focus hints.
        - After typing into a search or location field, if autocomplete surfaces or exact-match suggestions are visible, prefer choose_autocomplete_option before clicking a generic search button.
        - If the inspection shows visible selectable options such as reservation slots, appointment times, or checkout choices, you are still mid-flow. Choose the best matching visible option before using done.
        - If the current page still has required empty fields, verification blockers, or consent blockers, do not use done. Keep working the current page or ask only for the missing data.
        - A visible final submit button is only the final confirmation step when the page is otherwise ready to continue. If required fields or verification blockers remain, handle those first.
        - Never mention shell commands, files, local tools, or external browsers.
        - Do not ask the user to click controls that you can operate yourself.
        - If the goal is complete, return action done with a finalResponse.
        - Keep any prose outside the command brief.

        Allowed actions:
        - inspect_page
        - open_url
        - click_selector
        - click_text
        - type_text
        - select_option
        - choose_autocomplete_option
        - choose_grouped_option
        - pick_date
        - submit_form
        - press_key
        - scroll
        - wait_for_text
        - wait_for_selector
        - wait_for_navigation
        - wait_for_results
        - wait_for_dialog
        - wait_for_settle
        - capture_snapshot
        - done

        Emit exactly one XML block at the end of your response:
        <agenthub_browser_command>{"action":"inspect_page","selector":null,"text":null,"url":null,"key":null,"timeoutSeconds":null,"deltaY":null,"label":null,"finalResponse":null,"rationale":"..."}</agenthub_browser_command>
        """
    }

    private func parseBrowserAssistantResponse(_ text: String) -> (displayText: String, command: BrowserAgentCommand?) {
        BrowserAgentResponseParser.parse(text)
    }

    private func executeBrowserAgentCommand(
        _ command: BrowserAgentCommand,
        inspection: ChromiumInspection?,
        goalFocusTerms: [String],
        controller: ChromiumBrowserController,
        requireApproval: Bool = true
    ) async throws -> BrowserAgentExecutionResult {
        let resolution = BrowserSemanticResolver.resolve(command, inspection: inspection)
        try validateWorkflowBlockedAction(command: command, resolution: resolution, inspection: inspection)
        switch command.action {
        case .inspectPage:
            let inspection = try await controller.inspectCurrentPageForAgent()
            let controls = inspection.interactiveElements
                .prefix(5)
                .map { "\($0.label.isEmpty ? $0.text : $0.label) [\($0.selector)]" }
                .joined(separator: ", ")
            let workflowSummary = BrowserPageAnalyzer.workflow(for: inspection).map {
                let missing = $0.requirements.prefix(3).map(\.label).joined(separator: ", ")
                return " Workflow: \($0.stage) (ready: \($0.readyToContinue), success: \($0.hasSuccessSignal), failure: \($0.hasFailureSignal), final boundary: \($0.hasFinalConfirmationBoundary), missing: \(missing.isEmpty ? "none" : missing))."
            } ?? ""
            let summary = """
            Inspected \(inspection.title) at \(inspection.url). Stage: \(inspection.pageStage). Semantic targets: \(inspection.semanticTargets.count). Forms: \(inspection.forms.count), control groups: \(inspection.controlGroups.count), autocomplete surfaces: \(inspection.autocompleteSurfaces.count), date pickers: \(inspection.datePickers.count), notices: \(inspection.notices.count), step indicators: \(inspection.stepIndicators.count), result lists: \(inspection.resultLists.count), cards: \(inspection.cards.count), dialogs: \(inspection.dialogs.count), transactional boundaries: \(inspection.transactionalBoundaries.count).\(workflowSummary) Top controls: \(controls).
            """
            return BrowserAgentExecutionResult(summary: summary, inspection: inspection)
        case .openURL:
            guard let url = command.url else {
                throw ChromiumBrowserActionError(message: "open_url requires a url.")
            }
            let state = try await controller.openURLForAgent(url)
            return BrowserAgentExecutionResult(summary: "Opened \(state.urlString). Current title: \(state.title).", inspection: nil)
        case .clickSelector:
            try validateGoalFocusedSelection(command: command, resolution: resolution, inspection: inspection, goalFocusTerms: goalFocusTerms)
            if let selector = resolution.selector {
                _ = try await controller.clickSelectorForAgent(
                    selector,
                    label: resolution.label,
                    transactionalKind: resolution.transactionalKind,
                    requireApproval: requireApproval
                )
                let inspection = try await controller.inspectCurrentPageForAgent()
                let targetText = resolution.label ?? selector
                return BrowserAgentExecutionResult(summary: "Clicked semantic target \(targetText). Current page: \(inspection.url).", inspection: inspection)
            }
            guard let selector = command.selector else {
                throw ChromiumBrowserActionError(message: "click_selector requires a selector or semantic label.")
            }
            _ = try await controller.clickSelectorForAgent(selector, label: command.label, requireApproval: requireApproval)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Clicked selector \(selector). Current page: \(inspection.url).", inspection: inspection)
        case .clickText:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "click_text requires text.")
            }
            try validateGoalFocusedSelection(command: command, resolution: resolution, inspection: inspection, goalFocusTerms: goalFocusTerms)
            if let selector = resolution.selector {
                _ = try await controller.clickSelectorForAgent(
                    selector,
                    label: resolution.label ?? text,
                    transactionalKind: resolution.transactionalKind,
                    requireApproval: requireApproval
                )
                let inspection = try await controller.inspectCurrentPageForAgent()
                return BrowserAgentExecutionResult(summary: "Clicked semantic target \(resolution.label ?? text). Current page: \(inspection.url).", inspection: inspection)
            }
            _ = try await controller.clickTextForAgent(text, label: command.label, requireApproval: requireApproval)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Clicked visible text match \(text). Current page: \(inspection.url).", inspection: inspection)
        case .typeText:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "type_text requires text.")
            }
            guard let selector = resolution.selector ?? command.selector else {
                throw ChromiumBrowserActionError(message: "type_text requires a selector or semantic label.")
            }
            _ = try await controller.typeTextForAgent(text, selector: selector)
            let inspection = try await controller.inspectCurrentPageForAgent()
            let autocompleteHint = inspection.autocompleteSurfaces.isEmpty ? "" : " Autocomplete options are available."
            return BrowserAgentExecutionResult(summary: "Typed \(text) into \(resolution.label ?? selector).\(autocompleteHint)", inspection: inspection)
        case .selectOption:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "select_option requires text.")
            }
            guard let selector = resolution.selector ?? command.selector else {
                throw ChromiumBrowserActionError(message: "select_option requires a selector or semantic label.")
            }
            _ = try await controller.selectOptionForAgent(text, selector: selector)
            return BrowserAgentExecutionResult(summary: "Selected option \(text) in \(resolution.label ?? selector).", inspection: nil)
        case .chooseAutocompleteOption:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "choose_autocomplete_option requires text.")
            }
            _ = try await controller.chooseAutocompleteOptionForAgent(text, selector: resolution.selector ?? command.selector)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Chose autocomplete option \(text) for \(resolution.label ?? command.label ?? "the active field").", inspection: inspection)
        case .chooseGroupedOption:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "choose_grouped_option requires text.")
            }
            _ = try await controller.chooseGroupedOptionForAgent(
                text,
                groupLabel: resolution.label ?? command.label,
                selector: resolution.selector ?? command.selector
            )
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Chose grouped option \(text) in \(resolution.label ?? command.label ?? "the matching group").", inspection: inspection)
        case .pickDate:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "pick_date requires text.")
            }
            _ = try await controller.pickDateForAgent(text, selector: resolution.selector ?? command.selector)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Picked date \(text) for \(resolution.label ?? command.label ?? "the matching date field").", inspection: inspection)
        case .submitForm:
            _ = try await controller.submitFormForAgent(
                selector: resolution.selector ?? command.selector,
                label: resolution.label ?? command.label,
                transactionalKind: resolution.transactionalKind,
                requireApproval: requireApproval
            )
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Submitted \(resolution.label ?? command.label ?? "the best matching form").", inspection: inspection)
        case .pressKey:
            let key = command.key ?? command.text
            guard let key else {
                throw ChromiumBrowserActionError(message: "press_key requires a key.")
            }
            _ = try await controller.pressKeyForAgent(key)
            return BrowserAgentExecutionResult(summary: "Pressed key \(key).", inspection: nil)
        case .scroll:
            let deltaY = command.deltaY ?? 600
            _ = try await controller.scrollForAgent(deltaY: deltaY)
            let state = await MainActor.run { controller.browserSnapshot() }
            return BrowserAgentExecutionResult(summary: "Scrolled the page by \(Int(deltaY)) points on \(state.urlString).", inspection: nil)
        case .waitForText:
            guard let text = command.text else {
                throw ChromiumBrowserActionError(message: "wait_for_text requires text.")
            }
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForTextForAgent(text, timeout: timeout)
            return BrowserAgentExecutionResult(summary: "Observed \(probe.matchCount) visible matches for \(text) on \(probe.url).", inspection: nil)
        case .waitForSelector:
            guard let selector = command.selector else {
                throw ChromiumBrowserActionError(message: "wait_for_selector requires a selector.")
            }
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForSelectorForAgent(selector, timeout: timeout)
            return BrowserAgentExecutionResult(summary: "Observed selector \(selector) on \(probe.url).", inspection: nil)
        case .waitForNavigation:
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForNavigationForAgent(expectedURLFragment: command.url, timeout: timeout)
            return BrowserAgentExecutionResult(summary: "Observed navigation to \(probe.url).", inspection: nil)
        case .waitForResults:
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForResultsForAgent(expectedText: command.text, timeout: timeout)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Observed \(probe.resultCount) visible results on \(probe.url).", inspection: inspection)
        case .waitForDialog:
            let timeout = command.timeoutSeconds ?? 8
            let probe = try await controller.waitForDialogForAgent(expectedText: command.text, timeout: timeout)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Observed dialog \(probe.label.isEmpty ? "state" : probe.label) on \(probe.url).", inspection: inspection)
        case .waitForSettle:
            let timeout = command.timeoutSeconds ?? 8
            let state = try await controller.waitForSettleForAgent(timeout: timeout)
            let inspection = try await controller.inspectCurrentPageForAgent()
            return BrowserAgentExecutionResult(summary: "Page settled at \(state.urlString).", inspection: inspection)
        case .captureSnapshot:
            let artifact = try await controller.captureScrolledSnapshotForAgent(label: command.label)
            return BrowserAgentExecutionResult(summary: "Captured browser snapshot at \(artifact.filePath).", inspection: nil)
        case .done:
            return BrowserAgentExecutionResult(summary: command.finalResponse ?? "Browser task completed.", inspection: nil)
        }
    }

    private func parseAssistantResponse(_ text: String) -> (displayText: String, proposal: TaskProposal?) {
        let browserStripped = BrowserAgentResponseParser.parse(text).displayText
        let pattern = #"<agenthub_task_proposal>([\s\S]*?)</agenthub_task_proposal>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (browserStripped.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let range = NSRange(browserStripped.startIndex..<browserStripped.endIndex, in: browserStripped)
        guard let match = regex.firstMatch(in: browserStripped, options: [], range: range),
              let proposalRange = Range(match.range(at: 1), in: browserStripped),
              let fullRange = Range(match.range(at: 0), in: browserStripped) else {
            return (browserStripped.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let payload = String(browserStripped[proposalRange])
        let stripped = browserStripped.replacingCharacters(in: fullRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TaskProposalPayload.self, from: data) else {
            return (stripped, nil)
        }

        let proposal = TaskProposal(
            id: UUID(),
            title: decoded.title,
            instructions: decoded.instructions,
            scheduleType: decoded.scheduleType,
            scheduleValue: decoded.scheduleValue,
            runtimeMode: decoded.runtimeMode,
            repoPath: decoded.externalDirectory ?? decoded.repoPath,
            runNow: decoded.runNow
        )
        return (stripped, proposal)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func performCodexTurn(
        prompt: String,
        session: inout AssistantSession,
        config: CodexLaunchConfig,
        forwardAssistantLines: Bool
    ) async throws -> BrowserCodexTurnResult {
        let runtimeStream = runtime.streamEvents()
        var assistantLines: [String] = []
        var streamedAssistantText = ""
        var streamedDisplayText = ""
        var stderrLines: [String] = []
        var identifiedThreadId: String?

        let bridgeTask = Task {
            for await event in runtimeStream {
                switch event {
                case let .stdoutLine(line):
                    assistantLines.append(line)
                    streamedAssistantText += streamedAssistantText.isEmpty ? line : "\n\(line)"
                    if forwardAssistantLines {
                        let sanitizedLine = nextSanitizedAssistantDelta(
                            from: streamedAssistantText,
                            previousDisplayText: &streamedDisplayText
                        )
                        if !sanitizedLine.isEmpty {
                            emit(.assistantDelta(sanitizedLine))
                        }
                    }
                case let .stderrLine(line):
                    stderrLines.append(line)
                case let .threadIdentified(threadId):
                    identifiedThreadId = threadId
                case .started, .completed:
                    break
                case let .failed(message):
                    stderrLines.append(message)
                }
            }
        }

        let result: CodexExecutionResult
        if let threadId = session.codexThreadId {
            result = try await runtime.resumeThread(threadId: threadId, prompt: prompt, config: config)
        } else {
            result = try await runtime.startNewThread(prompt: prompt, config: config)
            if let threadId = result.threadId {
                session.codexThreadId = threadId
            }
        }

        _ = await bridgeTask.result

        if let identifiedThreadId {
            session.codexThreadId = identifiedThreadId
        }

        let assistantText = assistantLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrText = (stderrLines.isEmpty ? result.stderr : stderrLines.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserCodexTurnResult(assistantText: assistantText, stderrText: stderrText, result: result)
    }

    private func nextSanitizedAssistantDelta(
        from fullAssistantText: String,
        previousDisplayText: inout String
    ) -> String {
        let parsedDisplayText = BrowserAgentResponseParser.parse(fullAssistantText).displayText
        guard parsedDisplayText != previousDisplayText else {
            return ""
        }

        let delta: String
        if parsedDisplayText.hasPrefix(previousDisplayText) {
            delta = String(parsedDisplayText.dropFirst(previousDisplayText.count))
        } else {
            delta = parsedDisplayText
        }
        previousDisplayText = parsedDisplayText
        return delta.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persistBrowserRunArtifacts(
        outcome: String,
        goalText: String,
        initialURL: String?,
        session: AssistantSession,
        controller: ChromiumBrowserController,
        inspectionHistory: [ChromiumInspection],
        recentHistory: [String],
        finalSummary: String,
        scenarioMetadata: BrowserScenarioMetadata? = nil
    ) async throws {
        var captureWarnings: [String] = []
        do {
            _ = try await controller.captureScrolledSnapshotForAgent(label: outcome)
        } catch {
            captureWarnings.append("Automatic final snapshot failed: \(error.localizedDescription)")
        }
        let artifacts = await MainActor.run { controller.browserDebugArtifacts() }
        let record = BrowserRunArtifactRecord(
            createdAt: Date(),
            sessionId: session.id.uuidString,
            threadId: session.codexThreadId,
            outcome: outcome,
            goalText: goalText,
            initialURL: initialURL,
            scenarioID: scenarioMetadata?.id,
            scenarioTitle: scenarioMetadata?.title,
            scenarioCategory: scenarioMetadata?.category ?? BrowserScenarioClassifier.category(forGoalText: goalText, initialURL: initialURL),
            finalSummary: finalSummary,
            recentHistory: recentHistory,
            inspectionHistory: inspectionHistory,
            captureWarnings: captureWarnings,
            browserArtifacts: artifacts
        )

        let directory = paths.logsDirectory
            .appendingPathComponent("browser-agent-runs", isDirectory: true)
            .appendingPathComponent(session.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let slug = outcome
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let fileURL = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(slug).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
    }

    private func retryBrowserAgentCommandIfPossible(
        _ command: BrowserAgentCommand,
        staleInspection: ChromiumInspection?,
        refreshedInspection: ChromiumInspection,
        goalFocusTerms: [String],
        controller: ChromiumBrowserController,
        requireApproval: Bool = true
    ) async throws -> BrowserAgentExecutionResult? {
        guard let resolution = BrowserSemanticResolver.bestEffortRetarget(
            command,
            staleInspection: staleInspection,
            refreshedInspection: refreshedInspection
        ) else {
            return nil
        }

        let retargetedCommand = apply(resolution: resolution, to: command)
        let result = try await executeBrowserAgentCommand(
            retargetedCommand,
            inspection: refreshedInspection,
            goalFocusTerms: goalFocusTerms,
            controller: controller,
            requireApproval: requireApproval
        )
        let targetDescription = resolution.label ?? resolution.selector ?? "the refreshed semantic target"
        return BrowserAgentExecutionResult(
            summary: "Recovered by re-targeting to \(targetDescription). \(result.summary)",
            inspection: result.inspection
        )
    }

    private func apply(resolution: BrowserSemanticResolution, to command: BrowserAgentCommand) -> BrowserAgentCommand {
        var updated = command
        if let selector = resolution.selector {
            updated.selector = selector
        }
        if let label = resolution.label {
            updated.label = label
        }
        if command.action == .clickText, updated.selector != nil {
            updated.action = .clickSelector
        }
        return updated
    }

    private func browserActionSignature(_ command: BrowserAgentCommand, url: String) -> String {
        let selector = command.selector ?? "-"
        let text = command.text ?? "-"
        let targetURL = command.url ?? "-"
        let key = command.key ?? "-"
        return "\(url)|\(command.action.rawValue)|\(selector)|\(text)|\(targetURL)|\(key)"
    }

    private func validateGoalFocusedSelection(
        command: BrowserAgentCommand,
        resolution: BrowserSemanticResolution,
        inspection: ChromiumInspection?,
        goalFocusTerms: [String]
    ) throws {
        guard !goalFocusTerms.isEmpty else { return }
        guard let target = resolution.target else { return }
        let isResultsPage = inspection?.pageStage == "results" || inspection?.bookingFunnel?.stage == "results"
        let isReserveSlotTarget = isResultsPage && target.kind == "slot_option" && target.transactionalKind == "booking_slot"
        guard ["result_card", "primary_action", "autocomplete"].contains(target.kind) || isReserveSlotTarget else { return }
        let targetLabel = resolution.label ?? target.label
        guard goalFocusTermsMatch(label: targetLabel, focusTerms: goalFocusTerms) else {
            throw ChromiumBrowserActionError(message: "Selected result does not match the goal focus: \(targetLabel).")
        }
    }

    private func validateWorkflowBlockedAction(
        command: BrowserAgentCommand,
        resolution: BrowserSemanticResolution,
        inspection: ChromiumInspection?
    ) throws {
        guard let workflow = BrowserPageAnalyzer.workflow(for: inspection) else {
            return
        }
        let promptableRequirement = nextPromptableRequirement(in: inspection)
        guard !workflow.requirements.isEmpty || promptableRequirement != nil else {
            return
        }

        let detail = (resolution.label ?? command.label ?? command.text ?? command.selector ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.lowercased()
        let missing = (workflow.requirements.isEmpty ? [promptableRequirement].compactMap { $0?.label } : workflow.requirements.prefix(3).map(\.label))
            .joined(separator: ", ")
        let isNoiseAction = normalizedDetail.contains("use email instead")
            || normalizedDetail.contains("use phone instead")
            || normalizedDetail.contains("sign in")
            || normalizedDetail.contains("log in")
            || normalizedDetail.contains("login")
            || normalizedDetail.contains("skip to main content")
            || normalizedDetail.contains("dismiss")
            || normalizedDetail.contains("close")
        let isBlockedFinalAction = resolution.transactionalKind == "final_confirmation"
            || (command.action == .submitForm && workflow.hasFinalConfirmationBoundary)

        guard isNoiseAction || isBlockedFinalAction else { return }
        throw ChromiumBrowserActionError(
            message: "The page still requires input before this action can continue. Missing requirements: \(missing)."
        )
    }

    private func pendingApprovalCommand(from inspection: ChromiumInspection?) -> BrowserAgentCommand? {
        guard let inspection,
              let boundary = BrowserTransactionalGuard.highConfidenceFinalBoundary(in: inspection) else {
            return nil
        }
        guard BrowserTransactionalGuard.approvalShouldBeRequired(
            actionName: BrowserAgentAction.clickSelector.rawValue,
            detail: boundary.label,
            transactionalKind: boundary.kind,
            inspection: inspection
        ) else {
            return nil
        }

        let selector = boundary.selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { return nil }

        let label = boundary.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return BrowserAgentCommand(
            action: .clickSelector,
            url: nil,
            selector: selector,
            text: nil,
            key: nil,
            timeoutSeconds: nil,
            deltaY: nil,
            label: label.isEmpty ? nil : label,
            finalResponse: nil,
            rationale: "Complete the approved final confirmation step."
        )
    }

    private func approvalBoundaryLabelIfNeeded(
        for command: BrowserAgentCommand,
        inspection: ChromiumInspection?
    ) -> String? {
        let resolution = BrowserSemanticResolver.resolve(command, inspection: inspection)
        let detail = resolution.label
            ?? command.label
            ?? command.text
            ?? command.selector
            ?? command.url
            ?? command.action.rawValue
        guard BrowserTransactionalGuard.approvalShouldBeRequired(
            actionName: command.action.rawValue,
            detail: detail,
            transactionalKind: resolution.transactionalKind,
            inspection: inspection
        ) else {
            return nil
        }
        return detail
    }

    private func browserProgressSnapshot(state: ChromiumBrowserState, inspection: ChromiumInspection?) -> BrowserProgressSnapshot {
        let workflow = BrowserPageAnalyzer.workflow(for: inspection)
        return BrowserProgressSnapshot(
            url: state.urlString,
            title: state.title,
            pageStage: inspection?.pageStage ?? "unknown",
            workflowStage: workflow?.stage ?? "unknown",
            formCount: inspection?.forms.count ?? 0,
            resultListCount: inspection?.resultLists.count ?? 0,
            cardCount: inspection?.cards.count ?? 0,
            dialogLabels: (inspection?.dialogs ?? []).prefix(2).map { $0.label.lowercased() },
            boundaryKinds: (inspection?.transactionalBoundaries ?? []).prefix(3).map { $0.kind.lowercased() },
            requirementKinds: (workflow?.requirements ?? []).prefix(4).map { $0.kind.lowercased() },
            primaryActionLabels: (inspection?.primaryActions ?? []).prefix(4).map { $0.label.lowercased() },
            semanticTargetLabels: (inspection?.semanticTargets ?? []).prefix(6).map { $0.label.lowercased() },
            topControlLabels: (inspection?.interactiveElements ?? [])
                .prefix(5)
                .map { ($0.label.isEmpty ? $0.text : $0.label).lowercased() }
        )
    }

    private func isRecoverableBrowserError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("no element matched")
            || normalized.contains("no visible element matched")
            || normalized.contains("no autocomplete option matched")
            || normalized.contains("no grouped control option matched")
            || normalized.contains("no visible date matched")
            || normalized.contains("does not match the goal focus")
            || normalized.contains("still requires input before this action can continue")
            || normalized.contains("timed out waiting for selector")
            || normalized.contains("timed out waiting for dialog")
            || normalized.contains("timed out waiting for search results")
    }

    private func goalFocusTermsMatch(label: String, focusTerms: [String]) -> Bool {
        let normalizedLabelTokens = Set(tokenize(label))
        guard !normalizedLabelTokens.isEmpty else { return false }

        var strongestRequiredMatch = false
        for (index, term) in focusTerms.enumerated() {
            let tokens = tokenize(term)
            guard !tokens.isEmpty else { continue }
            let matchedCount = tokens.filter { normalizedLabelTokens.contains($0) }.count
            let requiredCount = max(1, Int(ceil(Double(tokens.count) * (index == 0 ? 0.5 : 0.34))))
            if index == 0 {
                strongestRequiredMatch = matchedCount >= requiredCount
                if !strongestRequiredMatch {
                    return false
                }
            }
        }
        return strongestRequiredMatch
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !$0.allSatisfy(\.isNumber) }
    }

    private func incompleteBrowserGoalReason(goalText: String, inspection: ChromiumInspection?) -> String? {
        guard isTransactionalBrowserGoal(goalText), let inspection else {
            return nil
        }
        if let workflow = BrowserPageAnalyzer.workflow(for: inspection),
           workflow.stage == "selection",
           inspection.semanticTargets.contains(where: { $0.kind == "slot_option" }) {
            let visibleSlotLabels = ((inspection.booking?.availableSlots ?? []).map(\.label)
                + inspection.semanticTargets.filter { $0.kind == "slot_option" }.map(\.label))
                .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !visibleSlotLabels.isEmpty else { return nil }
            let preview = visibleSlotLabels.prefix(3).joined(separator: ", ")
            return "Visible selectable options are still available on the current page (\(preview)). The task is not complete until you choose the best matching option and advance to the details or review step."
        }
        if let workflow = BrowserPageAnalyzer.workflow(for: inspection),
           ["details_form", "verification", "review", "final_submit", "success"].contains(workflow.stage) {
            return nil
        }
        return nil
    }

    private func isTransactionalBrowserGoal(_ goalText: String) -> Bool {
        let normalized = goalText.lowercased()
        return normalized.contains("reservation")
            || normalized.contains("reserve")
            || normalized.contains("book ")
            || normalized.contains("booking")
            || normalized.contains("checkout")
            || normalized.contains("flight")
            || normalized.contains("hotel")
    }

    private func browserBookingGuidanceSection(goalText: String, inspection: ChromiumInspection?) -> String {
        guard isTransactionalBrowserGoal(goalText), let inspection else {
            return "Workflow progress: none detected."
        }

        guard let workflow = BrowserPageAnalyzer.workflow(for: inspection) else {
            return "Workflow progress: none detected."
        }

        var lines = [
            "Workflow progress:",
            "- stage: \(workflow.stage)",
            "- ready to continue without more user data: \(workflow.readyToContinue ? "yes" : "no")"
        ]

        let visibleSlots = ((inspection.booking?.availableSlots ?? []).map(\.label)
            + inspection.semanticTargets.filter { $0.kind == "slot_option" }.map(\.label))
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        if !workflow.requirements.isEmpty {
            lines.append("- missing requirements: \(workflow.requirements.prefix(4).map(\.label).joined(separator: ", "))")
            lines.append("- required next step: satisfy the missing requirements on the current page before treating the flow as complete")
        } else if !visibleSlots.isEmpty {
            lines.append("- visible selectable options: \(visibleSlots.prefix(5).joined(separator: ", "))")
            lines.append("- required next step: click the best matching visible option; do not stop yet")
        } else if workflow.stage == "review" || workflow.stage == "final_submit" {
            lines.append("- the flow has advanced to review/final submit; stop only before the actual final confirmation action")
        } else {
            lines.append("- next objective: keep advancing toward the detail, review, or final-submit step")
        }

        return lines.joined(separator: "\n")
    }

    private func isReserveSlotLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("reserve table at") || normalized.contains("book table at")
    }

    private func browserRecoverySummary(
        for command: BrowserAgentCommand,
        message: String,
        inspection: ChromiumInspection,
        progressChanged: Bool
    ) -> String {
        let dialogSummary = inspection.dialogs.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let actionSummary = inspection.primaryActions.prefix(3).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let autocompleteSummary = inspection.autocompleteSurfaces.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let groupSummary = inspection.controlGroups.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let dateSummary = inspection.datePickers.prefix(2).map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")
        let stageSummary = inspection.pageStage
        let prefix = progressChanged
            ? "The target reported an error, but the page state changed."
            : "The target appears stale or the action was a no-op."

        switch command.action {
        case .typeText, .chooseAutocompleteOption:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible autocomplete inputs: \(autocompleteSummary.isEmpty ? "none" : autocompleteSummary)."
        case .chooseGroupedOption:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible grouped controls: \(groupSummary.isEmpty ? "none" : groupSummary)."
        case .pickDate:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible date controls: \(dateSummary.isEmpty ? "none" : dateSummary)."
        case .submitForm, .clickSelector, .clickText:
            let dialogText = dialogSummary.isEmpty ? "none" : dialogSummary
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible dialogs: \(dialogText). Top actions now: \(actionSummary.isEmpty ? "none" : actionSummary)."
        case .waitForResults:
            return "\(prefix) \(message) Page stage: \(stageSummary). Result lists: \(inspection.resultLists.count), cards: \(inspection.cards.count), top actions: \(actionSummary.isEmpty ? "none" : actionSummary)."
        case .waitForDialog:
            return "\(prefix) \(message) Page stage: \(stageSummary). Visible dialogs: \(dialogSummary.isEmpty ? "none" : dialogSummary)."
        default:
            return "\(prefix) \(message) Page stage: \(stageSummary). Inspection was refreshed with \(inspection.interactiveElements.count) visible interactive controls."
        }
    }

    private func emit(_ event: ChatSessionEvent) {
        stateLock.lock()
        let continuation = continuation
        stateLock.unlock()
        continuation?.yield(event)
    }

    private func finishStream() {
        stateLock.lock()
        let continuation = continuation
        self.continuation = nil
        stateLock.unlock()
        continuation?.finish()
    }

    private func formattedLocationSuffix(_ locationHint: String?) -> String {
        guard let locationHint,
              !locationHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return " in \(locationHint)"
    }

    private func persistAssistantMessage(_ text: String, session: AssistantSession, shouldStore: Bool) throws {
        guard shouldStore else { return }
        let assistantMessage = Message(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            text: text,
            source: .codexStdout,
            createdAt: Date()
        )
        try sessionStore.appendMessage(assistantMessage)
    }

    private func emitAssistantMessage(
        _ text: String,
        session: AssistantSession? = nil,
        shouldStore: Bool = false
    ) throws {
        if let session {
            try persistAssistantMessage(text, session: session, shouldStore: shouldStore)
        }
        emit(.assistantMessage(text))
    }
}

private struct TaskProposalPayload: Decodable {
    var title: String
    var instructions: String
    var scheduleType: TaskScheduleType
    var scheduleValue: String
    var runtimeMode: RuntimeMode
    var externalDirectory: String?
    var repoPath: String?
    var runNow: Bool
}

private struct BrowserCodexTurnResult {
    let assistantText: String
    let stderrText: String
    let result: CodexExecutionResult
}

private struct BrowserRunArtifactRecord: Codable {
    let createdAt: Date
    let sessionId: String
    let threadId: String?
    let outcome: String
    let goalText: String
    let initialURL: String?
    let scenarioID: String?
    let scenarioTitle: String?
    let scenarioCategory: String
    let finalSummary: String
    let recentHistory: [String]
    let inspectionHistory: [ChromiumInspection]
    let captureWarnings: [String]
    let browserArtifacts: ChromiumBrowserDebugArtifacts
}

private struct BrowserProgressSnapshot: Equatable {
    let url: String
    let title: String
    let pageStage: String
    let workflowStage: String
    let formCount: Int
    let resultListCount: Int
    let cardCount: Int
    let dialogLabels: [String]
    let boundaryKinds: [String]
    let requirementKinds: [String]
    let primaryActionLabels: [String]
    let semanticTargetLabels: [String]
    let topControlLabels: [String]
}
