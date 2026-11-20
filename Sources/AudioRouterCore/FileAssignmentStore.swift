import Foundation

public enum AssignmentStoreError: Error, Equatable, LocalizedError {
    /// The file couldn't be decoded. It was moved to `backup` so a fresh one can be written.
    case corrupted(backup: URL)
    /// The file was written by a newer Audio Router. It is left untouched.
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .corrupted(let backup):
            "Your saved choices were unreadable and have been reset. A copy is at \(backup.lastPathComponent)."
        case .unsupportedVersion(let v):
            "Your saved choices come from a newer Audio Router (format \(v)). Update the app to use them."
        }
    }
}

/// Stores choices as versioned JSON in Application Support.
///
/// - Atomic: writes go to a temp file that replaces the old one in a single rename,
///   so a crash mid-save leaves either the old or the new file, never half of one.
/// - Consistent: the file is versioned and validated on load; unreadable files are quarantined.
/// - Durable: every change is written before it is applied (see `RouterEngine.assign`).
@MainActor
public final class FileAssignmentStore: AssignmentStore {
    public static let currentVersion = 1

    private struct Document: Codable {
        var version: Int
        var assignments: [String: Assignment]
    }

    private let fileURL: URL
    private let legacySource: (() -> [String: String]?)?
    private let fileManager = FileManager.default

    /// - Parameter legacySource: returns choices saved by v1.0 (bundle ID -> device UID), if any.
    public init(fileURL: URL, legacySource: (() -> [String: String]?)? = nil) {
        self.fileURL = fileURL
        self.legacySource = legacySource
    }

    /// `~/Library/Application Support/AudioRouter/assignments.json`, migrating from UserDefaults.
    public static func standard() -> FileAssignmentStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("AudioRouter", isDirectory: true)
            .appendingPathComponent("assignments.json")
        return FileAssignmentStore(fileURL: url) {
            UserDefaults.standard.dictionary(forKey: "assignments") as? [String: String]
        }
    }

    public func load() throws -> [String: Assignment] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return try migrateLegacy() }

        let data = try Data(contentsOf: fileURL)
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw AssignmentStoreError.corrupted(backup: try quarantine())
        }
        guard document.version <= Self.currentVersion else {
            throw AssignmentStoreError.unsupportedVersion(document.version)
        }
        return document.assignments
    }

    public func save(_ assignments: [String: Assignment]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(version: Self.currentVersion, assignments: assignments))
        try data.write(to: fileURL, options: .atomic)
    }

    private func migrateLegacy() throws -> [String: Assignment] {
        guard let legacy = legacySource?(), !legacy.isEmpty else { return [:] }
        // v1.0 stored only the device UID; it doubles as the name until the device is seen again.
        let migrated = legacy.mapValues { Assignment(deviceUID: $0, deviceName: $0) }
        try save(migrated)
        return migrated
    }

    private func quarantine() throws -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try? fileManager.removeItem(at: backup)
        try fileManager.moveItem(at: fileURL, to: backup)
        return backup
    }
}
