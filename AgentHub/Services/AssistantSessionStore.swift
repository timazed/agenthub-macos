import Foundation

final class AssistantSessionStore {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let metadataEncoder: JSONEncoder
    private let messageEncoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock: FileLock

    init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager

        let metadataEncoder = JSONEncoder()
        metadataEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        metadataEncoder.dateEncodingStrategy = .iso8601
        self.metadataEncoder = metadataEncoder

        let messageEncoder = JSONEncoder()
        messageEncoder.outputFormatting = [.sortedKeys]
        messageEncoder.dateEncodingStrategy = .iso8601
        self.messageEncoder = messageEncoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.lock = FileLock(lockURL: paths.stateDirectory.appendingPathComponent("assistant-session.lock"))
    }

    func loadOrCreateDefault(personaId: String, provider: AuthProvider) throws -> AssistantSession {
        try lock.withLock {
            try paths.prepare(fileManager: fileManager)

            if fileManager.fileExists(atPath: paths.assistantMetadataURL(for: provider).path) {
                return try loadUnlocked(provider: provider)
            }

            if provider == .codex, fileManager.fileExists(atPath: paths.legacyAssistantMetadataURL.path) {
                let legacy = try loadLegacyUnlocked()
                try saveUnlocked(legacy)
                return legacy
            }

            let now = Date()
            let session = AssistantSession(
                id: UUID(),
                provider: provider,
                providerThreadID: nil,
                personaId: personaId,
                mode: .chatOnly,
                createdAt: now,
                updatedAt: now
            )
            try saveUnlocked(session)
            return session
        }
    }

    func save(_ session: AssistantSession) throws {
        try lock.withLock {
            try saveUnlocked(session)
        }
    }

    func loadMessages(provider: AuthProvider) throws -> [Message] {
        try lock.withLock {
            let transcriptURL = paths.assistantTranscriptURL(for: provider)
            if fileManager.fileExists(atPath: transcriptURL.path) {
                return try readMessages(from: transcriptURL)
            }
            if provider == .codex, fileManager.fileExists(atPath: paths.legacyAssistantTranscriptURL.path) {
                return try readMessages(from: paths.legacyAssistantTranscriptURL)
            }
            return []
        }
    }

    func appendMessage(_ message: Message, provider: AuthProvider) throws {
        try lock.withLock {
            try append(message: message, to: paths.assistantTranscriptURL(for: provider))
        }
    }

    private func loadUnlocked(provider: AuthProvider) throws -> AssistantSession {
        let data = try Data(contentsOf: paths.assistantMetadataURL(for: provider))
        return try decoder.decode(AssistantSession.self, from: data)
    }

    private func loadLegacyUnlocked() throws -> AssistantSession {
        let data = try Data(contentsOf: paths.legacyAssistantMetadataURL)
        return try decoder.decode(AssistantSession.self, from: data)
    }

    private func saveUnlocked(_ session: AssistantSession) throws {
        try paths.prepare(fileManager: fileManager)
        let data = try metadataEncoder.encode(session)
        let metadataURL = paths.assistantMetadataURL(for: session.provider)
        let transcriptURL = paths.assistantTranscriptURL(for: session.provider)
        try data.write(to: metadataURL, options: [.atomic])
        if !fileManager.fileExists(atPath: transcriptURL.path) {
            try Data().write(to: transcriptURL, options: [.atomic])
        }
    }

    private func append(message: Message, to url: URL) throws {
        try paths.prepare(fileManager: fileManager)
        if !fileManager.fileExists(atPath: url.path) {
            try Data().write(to: url, options: [.atomic])
        }

        var line = try messageEncoder.encode(message)
        line.append(0x0A)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
    }

    private func readMessages(from url: URL) throws -> [Message] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        let ndjsonMessages = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> Message? in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Message.self, from: lineData)
            }
        if !ndjsonMessages.isEmpty {
            return ndjsonMessages
        }

        return splitJSONObjects(from: data).compactMap { objectData in
            try? decoder.decode(Message.self, from: objectData)
        }
    }

    private func splitJSONObjects(from data: Data) -> [Data] {
        var objects: [Data] = []
        var objectStart: Int?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for (index, byte) in data.enumerated() {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if byte == UInt8(ascii: "\\") {
                    isEscaped = true
                } else if byte == UInt8(ascii: "\"") {
                    isInsideString = false
                }
                continue
            }

            switch byte {
            case UInt8(ascii: "\""):
                isInsideString = true
            case UInt8(ascii: "{"):
                if depth == 0 {
                    objectStart = index
                }
                depth += 1
            case UInt8(ascii: "}"):
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let start = objectStart {
                    objects.append(data.subdata(in: start..<(index + 1)))
                    objectStart = nil
                }
            default:
                continue
            }
        }

        return objects
    }
}
