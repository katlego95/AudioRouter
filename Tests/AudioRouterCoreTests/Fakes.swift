import Foundation
@testable import AudioRouterCore

// In-memory stand-ins for the Core Audio adapters, so engine behaviour is tested
// without touching real hardware.

@MainActor
final class FakeAudioSystem: AudioSystemProviding {
    var devices: [OutputDevice] = []
    var defaultID: UInt32 = 0
    var apps: [AudioApp] = []

    func outputDevices() -> [OutputDevice] { devices }
    func defaultOutputDeviceID() -> UInt32 { defaultID }
    func audioApps() -> [AudioApp] { apps }
}

@MainActor
final class FakeRoute: RouteHandle {
    let bundleID: String
    let deviceUID: String
    let processIDs: [UInt32]
    private(set) var stopCount = 0
    var isStopped: Bool { stopCount > 0 }

    init(bundleID: String, deviceUID: String, processIDs: [UInt32]) {
        self.bundleID = bundleID
        self.deviceUID = deviceUID
        self.processIDs = processIDs
    }

    func stop() { stopCount += 1 }
}

struct FakeRouteError: LocalizedError {
    var errorDescription: String? { "Could not tap app" }
}

@MainActor
final class FakeRouteFactory: RouteFactory {
    private(set) var made: [FakeRoute] = []
    /// Bundle IDs whose next route attempts should fail.
    var failing: Set<String> = []

    func makeRoute(bundleID: String, device: OutputDevice, processIDs: [UInt32]) throws -> RouteHandle {
        if failing.contains(bundleID) { throw FakeRouteError() }
        let route = FakeRoute(bundleID: bundleID, deviceUID: device.uid, processIDs: processIDs)
        made.append(route)
        return route
    }

    var live: [FakeRoute] { made.filter { !$0.isStopped } }
}

struct FakeStoreError: LocalizedError {
    var errorDescription: String? { "Disk full" }
}

@MainActor
final class InMemoryAssignmentStore: AssignmentStore {
    var saved: [String: Assignment]
    var failSaves = false
    var failLoad = false
    private(set) var saveCount = 0

    init(_ initial: [String: Assignment] = [:]) { saved = initial }

    func load() throws -> [String: Assignment] {
        if failLoad { throw FakeStoreError() }
        return saved
    }

    func save(_ assignments: [String: Assignment]) throws {
        if failSaves { throw FakeStoreError() }
        saved = assignments
        saveCount += 1
    }
}

enum Fixtures {
    static let speakers = OutputDevice(id: 73, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers", kind: .builtIn)
    static let soundcore = OutputDevice(id: 90, uid: "AA-BB-CC", name: "soundcore Select 4 Go", kind: .bluetooth)
    static let usb = OutputDevice(id: 91, uid: "USB-1", name: "AB13X USB Audio", kind: .usb)

    static let chrome = AudioApp(id: "com.google.Chrome", name: "Google Chrome", processIDs: [105, 107], isPlaying: true)
    static let vlc = AudioApp(id: "org.videolan.vlc", name: "VLC", processIDs: [120], isPlaying: true)

    static func assign(_ device: OutputDevice) -> Assignment {
        Assignment(deviceUID: device.uid, deviceName: device.name)
    }
}
