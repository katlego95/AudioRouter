import Foundation
import Testing
@testable import AudioRouterCore

@MainActor
@Suite("FileAssignmentStore: durable, atomic, self-healing settings")
struct FileAssignmentStoreTests {
    let dir: URL
    var file: URL { dir.appendingPathComponent("assignments.json") }

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRouterTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func missingFileLoadsEmpty() throws {
        let store = FileAssignmentStore(fileURL: file)
        #expect(try store.load().isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = FileAssignmentStore(fileURL: file)
        let value = ["org.videolan.vlc": Assignment(deviceUID: "AA-BB-CC", deviceName: "soundcore")]
        try store.save(value)
        #expect(try FileAssignmentStore(fileURL: file).load() == value)
    }

    @Test func createsParentDirectory() throws {
        try FileAssignmentStore(fileURL: file).save([:])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func savedFileIsVersioned() throws {
        try FileAssignmentStore(fileURL: file).save([:])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        #expect(json?["version"] as? Int == FileAssignmentStore.currentVersion)
    }

    @Test func corruptFileIsQuarantinedAndReported() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: file)
        let store = FileAssignmentStore(fileURL: file)

        #expect(throws: AssignmentStoreError.self) { try store.load() }
        // The broken file is moved aside so the next launch starts clean, and nothing is lost.
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt") }
        #expect(backups.count == 1)
        #expect(try store.load().isEmpty)
    }

    @Test func fileFromFutureVersionIsNotOverwrittenOrDeleted() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"version": 99, "assignments": {}}"#.utf8).write(to: file)
        let store = FileAssignmentStore(fileURL: file)
        #expect(throws: AssignmentStoreError.unsupportedVersion(99)) { try store.load() }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func migratesLegacyUserDefaultsOnce() throws {
        var legacyReads = 0
        let store = FileAssignmentStore(fileURL: file) {
            legacyReads += 1
            return ["org.videolan.vlc": "AA-BB-CC"]
        }
        let loaded = try store.load()
        #expect(loaded == ["org.videolan.vlc": Assignment(deviceUID: "AA-BB-CC", deviceName: "AA-BB-CC")])
        // Migration is persisted, so the legacy source isn't consulted again.
        _ = try store.load()
        #expect(legacyReads == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func saveReplacesFileAtomically() throws {
        let store = FileAssignmentStore(fileURL: file)
        try store.save(["a": Assignment(deviceUID: "1", deviceName: "One")])
        try store.save(["b": Assignment(deviceUID: "2", deviceName: "Two")])
        #expect(try store.load() == ["b": Assignment(deviceUID: "2", deviceName: "Two")])
        // No temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers == ["assignments.json"])
    }
}
