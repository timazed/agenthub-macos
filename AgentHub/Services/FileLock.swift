import Foundation
import Darwin

final class FileLock {
    private let lockURL: URL
    private let fileManager: FileManager

    init(lockURL: URL, fileManager: FileManager = .default) {
        self.lockURL = lockURL
        self.fileManager = fileManager
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: lockURL.path) {
            fileManager.createFile(atPath: lockURL.path, contents: Data())
        }

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: "FileLock", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to open lock file at \(lockURL.path)"])
        }

        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw NSError(domain: "FileLock", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to acquire lock for \(lockURL.path)"])
        }

        return try body()
    }
}
