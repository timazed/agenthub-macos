import Foundation

final class PersonaManager {
    private struct PersonaProfile: Codable {
        var name: String
        var profilePictureURL: String?
        var contactProfile: PersonaContactProfile?

        enum CodingKeys: String, CodingKey {
            case name
            case profilePictureURL = "profilePictureUrl"
            case contactProfile
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
                profilePictureURL: nil,
                contactProfile: nil
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
                profilePictureURL: existingProfile?.profilePictureURL,
                contactProfile: existingProfile?.contactProfile
            ),
            to: dir
        )
    }

    func loadContactProfile(personaId: String) -> PersonaContactProfile? {
        loadProfile(for: personaId)?.contactProfile
    }

    func updateContactProfile(personaId: String, contactProfile: PersonaContactProfile?) throws {
        let safeId = slugify(personaId)
        let dir = paths.personasDirectory.appendingPathComponent(safeId, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let existingProfile = loadProfile(for: safeId)
        let profile = PersonaProfile(
            name: existingProfile?.name ?? displayName(from: safeId),
            profilePictureURL: existingProfile?.profilePictureURL,
            contactProfile: contactProfile
        )
        try writeProfile(profile, to: dir)
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
        let profile = PersonaProfile(name: legacyName, profilePictureURL: nil, contactProfile: nil)
        try? writeProfile(profile, to: directory)
        return profile
    }
}

final class UserProfileManager {
    private let paths: AppPaths
    private let fileManager: FileManager

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func loadProfile() -> UserProfile? {
        if let profile = decodeProfile(at: paths.userProfileURL) {
            return profile
        }
        return decodeProfile(at: paths.legacyUserProfileURL)
    }

    func loadContactProfile() -> PersonaContactProfile? {
        guard let profile = loadProfile() else { return nil }
        let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitFirstName = profile.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitLastName = profile.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackNameParts = splitFullName(name)
        let firstName = emptyToNil(explicitFirstName) ?? fallbackNameParts?.firstName
        let lastName = emptyToNil(explicitLastName) ?? fallbackNameParts?.lastName
        let email = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneNumber = profile.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = emptyToNil(name)
            ?? [firstName, lastName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard [fullName, firstName, lastName, email, phoneNumber].contains(where: {
            guard let value = $0 else { return false }
            return !value.isEmpty
        }) else {
            return nil
        }

        return PersonaContactProfile(
            fullName: emptyToNil(fullName),
            firstName: firstName,
            lastName: lastName,
            email: emptyToNil(email),
            phoneNumber: emptyToNil(phoneNumber),
            addressLine1: nil,
            addressLine2: nil,
            city: nil,
            state: nil,
            postalCode: nil,
            country: nil
        )
    }

    private func decodeProfile(at url: URL) -> UserProfile? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func splitFullName(_ fullName: String?) -> (firstName: String, lastName: String)? {
        guard let fullName = emptyToNil(fullName) else { return nil }
        let parts = fullName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return (parts.first ?? "", parts.dropFirst().joined(separator: " "))
    }
}
