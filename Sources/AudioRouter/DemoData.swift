import Foundation
import AudioRouterCore

// Fake hardware used by `--render-preview` so contributors can iterate on the UI
// (and regenerate the README screenshots) without real devices or permissions.

@MainActor
final class DemoAudioSystem: AudioSystemProviding {
    static let speakers = OutputDevice(id: 1, uid: "demo-speakers", name: "MacBook Pro Speakers", kind: .builtIn)
    static let soundcore = OutputDevice(id: 2, uid: "demo-bt", name: "Soundcore Select 4 Go", kind: .bluetooth)
    static let usb = OutputDevice(id: 3, uid: "demo-usb", name: "AB13X USB Audio", kind: .usb)
    static let tv = OutputDevice(id: 4, uid: "demo-airplay", name: "Living Room TV", kind: .airPlay)

    func outputDevices() -> [OutputDevice] { [Self.speakers, Self.soundcore, Self.usb, Self.tv] }
    func defaultOutputDeviceID() -> UInt32 { Self.speakers.id }
    func audioApps() -> [AudioApp] {
        [
            AudioApp(id: "demo.chrome", name: "Google Chrome", processIDs: [1], isPlaying: true),
            AudioApp(id: "demo.vlc", name: "VLC", processIDs: [2], isPlaying: true),
            AudioApp(id: "demo.spotify", name: "Spotify", processIDs: [3], isPlaying: true),
            AudioApp(id: "demo.music", name: "Music", processIDs: [4], isPlaying: false),
            AudioApp(id: "demo.zoom", name: "Zoom", processIDs: [5], isPlaying: false),
        ]
    }
}

@MainActor
final class DemoRoute: RouteHandle {
    let bundleID: String, deviceUID: String, processIDs: [UInt32]
    init(_ b: String, _ d: String, _ p: [UInt32]) { bundleID = b; deviceUID = d; processIDs = p }
    func stop() {}
}

@MainActor
final class DemoRouteFactory: RouteFactory {
    func makeRoute(bundleID: String, device: OutputDevice, processIDs: [UInt32]) throws -> RouteHandle {
        DemoRoute(bundleID, device.uid, processIDs)
    }
}

@MainActor
final class DemoStore: AssignmentStore {
    var value: [String: Assignment] = [:]
    func load() throws -> [String: Assignment] { value }
    func save(_ assignments: [String: Assignment]) throws { value = assignments }
}

@MainActor
enum Demo {
    static func engine() -> RouterEngine {
        let store = DemoStore()
        store.value = [
            "demo.vlc": Assignment(deviceUID: DemoAudioSystem.soundcore.uid, deviceName: DemoAudioSystem.soundcore.name),
            "demo.spotify": Assignment(deviceUID: DemoAudioSystem.usb.uid, deviceName: DemoAudioSystem.usb.name),
            "demo.music": Assignment(deviceUID: "demo-gone", deviceName: "Kitchen HomePod"),
        ]
        return RouterEngine(system: DemoAudioSystem(), factory: DemoRouteFactory(), store: store)
    }
}
