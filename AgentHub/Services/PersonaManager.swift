import Foundation

final class PersonaManager {
    private struct PersonaProfile: Codable {
        var name: String
        var profilePictureURL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case profilePictureURL = "profilePictureUrl"
        }
    }

    private let paths: AppPaths
    private let fileManager: FileManager

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func defaultPersona() throws -> Persona {
        try validatePersona(personaId: "default")
    }

    func defaultPersonalityText() -> String {
        defaultInstructions
    }

    func defaultAgentName() -> String {
        persistedDefaultAgentName() ?? "Default"
    }

    func persistDefaultAgentName(_ name: String) throws {
        let normalizedName = normalizeName(name, fallback: defaultAgentName())
        let directory = personaDirectory(personaId: "default")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let existingProfile = loadProfile(for: "default")
        try writeProfile(
            PersonaProfile(
                name: normalizedName,
                profilePictureURL: existingProfile?.profilePictureURL
            ),
            to: directory
        )
    }

    private func persistedDefaultAgentName() -> String? {
        guard let name = loadProfile(for: "default")?.name else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func upsertDefaultPersona(name: String, instructions: String) throws -> Persona {
        let trimmedName = normalizeName(name, fallback: defaultAgentName())

        if (try? validatePersona(personaId: "default")) != nil {
            try updatePersona(personaId: "default", name: trimmedName, instructions: instructions)
            return try validatePersona(personaId: "default")
        }

        return try createPersona(name: trimmedName, instructions: instructions)
    }

    func updateDefaultPersonaName(_ name: String) throws {
        let instructions = try loadInstructions(personaId: "default")
        try updatePersona(
            personaId: "default",
            name: normalizeName(name, fallback: defaultAgentName()),
            instructions: instructions
        )
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
            let profile = loadProfile(for: id)
            return Persona(
                id: id,
                name: profile?.name ?? displayName(from: id),
                profilePictureURL: profile?.profilePictureURL,
                directoryPath: url.path
            )
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
        try writeProfile(
            PersonaProfile(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                profilePictureURL: nil
            ),
            to: dir
        )

        return Persona(
            id: personaId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            profilePictureURL: nil,
            directoryPath: dir.path
        )
    }

    func updatePersona(personaId: String, name: String, instructions: String) throws {
        let safeId = slugify(personaId)
        let dir = paths.personasDirectory.appendingPathComponent(safeId, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let agentsURL = dir.appendingPathComponent("AGENTS.md")
        try normalizeInstructions(instructions).write(to: agentsURL, atomically: true, encoding: .utf8)

        let existingProfile = loadProfile(for: safeId)
        try writeProfile(
            PersonaProfile(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                profilePictureURL: existingProfile?.profilePictureURL
            ),
            to: dir
        )
    }

    func loadInstructions(personaId: String) throws -> String {
        let url = personaDirectory(personaId: personaId).appendingPathComponent("AGENTS.md")
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "PersonaManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing AGENTS.md for persona \(personaId)"])
        }
        return try String(contentsOf: url, encoding: .utf8)
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

        let profile = loadProfile(for: personaId)
        let name = profile?.name ?? displayName(from: personaId)
        return Persona(
            id: personaId,
            name: name,
            profilePictureURL: profile?.profilePictureURL,
            directoryPath: dir.path
        )
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

    private func normalizeName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
        legacyDisplayName(for: id) ?? id
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func loadProfile(for id: String) -> PersonaProfile? {
        let directory = paths.personasDirectory
            .appendingPathComponent(slugify(id), isDirectory: true)
        let url = directory.appendingPathComponent("profile.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return migrateLegacyProfileIfNeeded(for: id, directory: directory)
        }
        guard let data = try? Data(contentsOf: url) else {
            return migrateLegacyProfileIfNeeded(for: id, directory: directory)
        }
        guard let profile = try? JSONDecoder().decode(PersonaProfile.self, from: data) else {
            return migrateLegacyProfileIfNeeded(for: id, directory: directory)
        }
        return profile
    }

    private func writeProfile(_ profile: PersonaProfile, to directory: URL) throws {
        let url = directory.appendingPathComponent("profile.json")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: url, options: .atomic)
    }

    private func legacyDisplayName(for id: String) -> String? {
        let url = paths.personasDirectory
            .appendingPathComponent(slugify(id), isDirectory: true)
            .appendingPathComponent("NAME.txt")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func migrateLegacyProfileIfNeeded(for id: String, directory: URL) -> PersonaProfile? {
        guard let legacyName = legacyDisplayName(for: id) else { return nil }
        let profile = PersonaProfile(name: legacyName, profilePictureURL: nil)
        try? writeProfile(profile, to: directory)
        return profile
    }
}
