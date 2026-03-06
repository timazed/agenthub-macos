import Foundation

final class PersonaManager {
    private let paths: AppPaths
    private let fileManager: FileManager

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func defaultPersona() throws -> Persona {
        try validatePersona(personaId: "default")
    }

    func list() throws -> [Persona] {
        try paths.prepare(fileManager: fileManager)

        let items = try fileManager.contentsOfDirectory(
            at: paths.personasDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let personas = items.compactMap { url -> Persona? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let agentsPath = url.appendingPathComponent("AGENTS.md").path
            guard fileManager.fileExists(atPath: agentsPath) else { return nil }
            let id = url.lastPathComponent
            return Persona(id: id, name: displayName(from: id), directoryPath: url.path)
        }

        if personas.isEmpty {
            _ = try createPersona(name: "Default", instructions: defaultInstructions)
            return try list()
        }

        return personas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createPersona(name: String, instructions: String) throws -> Persona {
        try paths.prepare(fileManager: fileManager)

        let baseId = slugify(name)
        let personaId = try uniquePersonaId(base: baseId)
        let dir = paths.personasDirectory.appendingPathComponent(personaId, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let agentsURL = dir.appendingPathComponent("AGENTS.md")
        try normalizeInstructions(instructions).write(to: agentsURL, atomically: true, encoding: .utf8)
        let nameURL = dir.appendingPathComponent("NAME.txt")
        try name.trimmingCharacters(in: .whitespacesAndNewlines).write(to: nameURL, atomically: true, encoding: .utf8)

        return Persona(id: personaId, name: name.trimmingCharacters(in: .whitespacesAndNewlines), directoryPath: dir.path)
    }

    func updatePersona(personaId: String, name: String, instructions: String) throws {
        let safeId = slugify(personaId)
        let dir = paths.personasDirectory.appendingPathComponent(safeId, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let agentsURL = dir.appendingPathComponent("AGENTS.md")
        try normalizeInstructions(instructions).write(to: agentsURL, atomically: true, encoding: .utf8)

        // Keep display name separate via NAME.txt for v0 minimal metadata.
        let nameURL = dir.appendingPathComponent("NAME.txt")
        try name.trimmingCharacters(in: .whitespacesAndNewlines).write(to: nameURL, atomically: true, encoding: .utf8)
    }

    func loadInstructions(personaId: String) throws -> String {
        let url = personaDirectory(personaId: personaId).appendingPathComponent("AGENTS.md")
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "PersonaManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing AGENTS.md for persona \(personaId)"])
        }
        return try String(contentsOf: url)
    }

    func personaDirectory(personaId: String) -> URL {
        paths.personasDirectory.appendingPathComponent(slugify(personaId), isDirectory: true)
    }

    func validatePersona(personaId: String) throws -> Persona {
        let dir = personaDirectory(personaId: personaId)
        let agents = dir.appendingPathComponent("AGENTS.md")
        guard fileManager.fileExists(atPath: agents.path) else {
            throw NSError(domain: "PersonaManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing AGENTS.md for persona \(personaId)"])
        }

        let name = loadDisplayName(for: personaId) ?? displayName(from: personaId)
        return Persona(id: personaId, name: name, directoryPath: dir.path)
    }

    private var defaultInstructions: String {
        """
        You are a concise, accurate assistant.
        Prioritize correctness and actionable output.
        """
    }

    private func uniquePersonaId(base: String) throws -> String {
        var candidate = base
        var index = 1

        while fileManager.fileExists(atPath: paths.personasDirectory.appendingPathComponent(candidate).path) {
            index += 1
            candidate = "\(base)-\(index)"
        }

        return candidate
    }

    private func normalizeInstructions(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultInstructions : trimmed + "\n"
    }

    private func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(mapped).replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "persona" : trimmed
    }

    private func displayName(from id: String) -> String {
        loadDisplayName(for: id) ?? id
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func loadDisplayName(for id: String) -> String? {
        let url = paths.personasDirectory
            .appendingPathComponent(slugify(id), isDirectory: true)
            .appendingPathComponent("NAME.txt")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
