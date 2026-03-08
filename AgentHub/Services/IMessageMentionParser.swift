import Foundation

final class IMessageMentionParser {
    struct ParsedCommand {
        var persona: Persona
        var prompt: String
    }

    private let personaManager: PersonaManager

    init(personaManager: PersonaManager) {
        self.personaManager = personaManager
    }

    func parse(_ text: String) throws -> ParsedCommand? {
        let personas = try personaManager.list()
            .sorted { $0.name.count > $1.name.count }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for persona in personas {
            guard let range = mentionRange(for: persona.name, in: trimmedText) else { continue }
            let prompt = trimmedPrompt(byRemoving: range, from: trimmedText)
            guard !prompt.isEmpty else { continue }
            return ParsedCommand(persona: persona, prompt: prompt)
        }

        return nil
    }

    private func mentionRange(for personaName: String, in text: String) -> Range<String.Index>? {
        let escapedName = NSRegularExpression.escapedPattern(for: personaName)
        let pattern = "(?i)(?:^|\\s)@\(escapedName)(?=$|\\s|[[:punct:]])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }
        return Range(match.range(at: 0), in: text)
    }

    private func trimmedPrompt(byRemoving mentionRange: Range<String.Index>, from text: String) -> String {
        var prompt = text
        prompt.removeSubrange(mentionRange)
        return prompt
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
