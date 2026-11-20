import Foundation
import Testing
@testable import AudioRouterCore

@Suite("RoutePlanner: decides which routes to start and stop")
struct RoutePlannerTests {
    let planner = RoutePlanner(retryDelay: 10)
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    typealias F = Fixtures

    private func plan(active: [ActiveRoute] = [],
                      assignments: [String: Assignment] = [:],
                      apps: [AudioApp] = [F.chrome, F.vlc],
                      devices: [OutputDevice] = [F.speakers, F.soundcore],
                      lastFailure: [String: Date] = [:]) -> RoutePlan {
        planner.plan(active: active, assignments: assignments, apps: apps, devices: devices,
                     lastFailure: lastFailure, now: now)
    }

    @Test func nothingAssignedMeansNothingToDo() {
        #expect(plan() == RoutePlan(stops: [], starts: []))
    }

    @Test func startsRouteForAssignedRunningApp() {
        let result = plan(assignments: [F.vlc.id: F.assign(F.soundcore)])
        #expect(result.stops.isEmpty)
        #expect(result.starts == [RouteStart(bundleID: F.vlc.id, device: F.soundcore, processIDs: [120])])
    }

    @Test func doesNotStartWhenAppIsNotRunning() {
        let result = plan(assignments: [F.vlc.id: F.assign(F.soundcore)], apps: [F.chrome])
        #expect(result.starts.isEmpty)
    }

    @Test func bluetoothDisconnectStopsRouteSoAppFallsBackToDefault() {
        let active = [ActiveRoute(bundleID: F.vlc.id, deviceUID: F.soundcore.uid, processIDs: [120])]
        let result = plan(active: active, assignments: [F.vlc.id: F.assign(F.soundcore)],
                          devices: [F.speakers])
        #expect(result.stops == [F.vlc.id])
        #expect(result.starts.isEmpty)
    }

    @Test func reconnectedDeviceIsRoutedAgain() {
        let result = plan(assignments: [F.vlc.id: F.assign(F.soundcore)], devices: [F.speakers, F.soundcore])
        #expect(result.starts.map(\.bundleID) == [F.vlc.id])
    }

    @Test func choosingSystemDefaultStopsRoute() {
        let active = [ActiveRoute(bundleID: F.vlc.id, deviceUID: F.soundcore.uid, processIDs: [120])]
        let result = plan(active: active, assignments: [:])
        #expect(result.stops == [F.vlc.id])
        #expect(result.starts.isEmpty)
    }

    @Test func switchingDeviceRestartsRouteOnNewDevice() {
        let active = [ActiveRoute(bundleID: F.vlc.id, deviceUID: F.soundcore.uid, processIDs: [120])]
        let result = plan(active: active, assignments: [F.vlc.id: F.assign(F.speakers)])
        #expect(result.stops == [F.vlc.id])
        #expect(result.starts == [RouteStart(bundleID: F.vlc.id, device: F.speakers, processIDs: [120])])
    }

    @Test func newHelperProcessRebuildsTheTap() {
        // Chrome spawned another helper: the old tap doesn't include it.
        let active = [ActiveRoute(bundleID: F.chrome.id, deviceUID: F.speakers.uid, processIDs: [105])]
        let result = plan(active: active, assignments: [F.chrome.id: F.assign(F.speakers)])
        #expect(result.stops == [F.chrome.id])
        #expect(result.starts.first?.processIDs == [105, 107])
    }

    @Test func healthyRouteIsLeftAlone() {
        let active = [ActiveRoute(bundleID: F.vlc.id, deviceUID: F.soundcore.uid, processIDs: [120])]
        let result = plan(active: active, assignments: [F.vlc.id: F.assign(F.soundcore)])
        #expect(result == RoutePlan(stops: [], starts: []))
    }

    @Test func recentFailureBacksOffBeforeRetrying() {
        let assignments = [F.vlc.id: F.assign(F.soundcore)]
        let justFailed = plan(assignments: assignments, lastFailure: [F.vlc.id: now.addingTimeInterval(-3)])
        #expect(justFailed.starts.isEmpty)

        let failedLongAgo = plan(assignments: assignments, lastFailure: [F.vlc.id: now.addingTimeInterval(-11)])
        #expect(failedLongAgo.starts.map(\.bundleID) == [F.vlc.id])
    }

    @Test func outputIsDeterministicallySorted() {
        let result = plan(assignments: [F.vlc.id: F.assign(F.soundcore), F.chrome.id: F.assign(F.speakers)])
        #expect(result.starts.map(\.bundleID) == [F.chrome.id, F.vlc.id])
    }
}

@Suite("RouteStatus: what the UI tells the user")
struct RouteStatusTests {
    typealias F = Fixtures
    let devices = [F.speakers, F.soundcore]

    @Test func unassignedFollowsSystemDefault() {
        let s = RouteStatus.resolve(bundleID: F.vlc.id, assignments: [:], activeDeviceUIDs: [:], devices: devices, errors: [:])
        #expect(s == .systemDefault)
    }

    @Test func activeRouteIsRouted() {
        let s = RouteStatus.resolve(bundleID: F.vlc.id, assignments: [F.vlc.id: F.assign(F.soundcore)],
                                    activeDeviceUIDs: [F.vlc.id: F.soundcore.uid], devices: devices, errors: [:])
        #expect(s == .routed(deviceName: "soundcore Select 4 Go"))
    }

    @Test func missingDeviceIsWaiting() {
        let s = RouteStatus.resolve(bundleID: F.vlc.id, assignments: [F.vlc.id: F.assign(F.soundcore)],
                                    activeDeviceUIDs: [:], devices: [F.speakers], errors: [:])
        #expect(s == .waitingForDevice(deviceName: "soundcore Select 4 Go"))
    }

    @Test func errorWinsOverConnecting() {
        let s = RouteStatus.resolve(bundleID: F.vlc.id, assignments: [F.vlc.id: F.assign(F.soundcore)],
                                    activeDeviceUIDs: [:], devices: devices, errors: [F.vlc.id: "boom"])
        #expect(s == .failed(message: "boom"))
    }

    @Test func presentDeviceWithoutRouteIsConnecting() {
        let s = RouteStatus.resolve(bundleID: F.vlc.id, assignments: [F.vlc.id: F.assign(F.soundcore)],
                                    activeDeviceUIDs: [:], devices: devices, errors: [:])
        #expect(s == .connecting(deviceName: "soundcore Select 4 Go"))
    }

    @Test func liveDeviceNameBeatsSavedName() {
        // The user renamed the speaker in Audio MIDI Setup; show the current name.
        let saved = Assignment(deviceUID: F.soundcore.uid, deviceName: "Old name")
        let s = RouteStatus.resolve(bundleID: F.vlc.id, assignments: [F.vlc.id: saved],
                                    activeDeviceUIDs: [F.vlc.id: F.soundcore.uid], devices: devices, errors: [:])
        #expect(s == .routed(deviceName: "soundcore Select 4 Go"))
    }
}
