import Foundation
import Testing
@testable import AudioRouterCore

@MainActor
@Suite("RouterEngine: end-to-end behaviour with fake hardware")
struct RouterEngineTests {
    typealias F = Fixtures
    let system = FakeAudioSystem()
    let factory = FakeRouteFactory()
    let store: InMemoryAssignmentStore

    init() {
        system.devices = [F.speakers, F.soundcore, F.usb]
        system.defaultID = F.speakers.id
        system.apps = [F.chrome, F.vlc]
        store = InMemoryAssignmentStore()
    }

    private func makeEngine(now: @escaping @MainActor () -> Date = { Date(timeIntervalSinceReferenceDate: 0) }) -> RouterEngine {
        RouterEngine(system: system, factory: factory, store: store, now: now)
    }

    @Test func refreshPublishesAppsDevicesAndDefault() {
        let engine = makeEngine()
        #expect(engine.apps.map(\.id) == [F.chrome.id, F.vlc.id])
        #expect(engine.devices == [F.speakers, F.soundcore, F.usb])
        #expect(engine.defaultDevice == F.speakers)
    }

    @Test func assigningRoutesTheAppAndPersists() {
        let engine = makeEngine()
        #expect(engine.assign(F.soundcore, to: F.vlc.id))
        #expect(factory.live.map(\.deviceUID) == [F.soundcore.uid])
        #expect(store.saved[F.vlc.id] == F.assign(F.soundcore))
        #expect(engine.status(for: F.vlc.id) == .routed(deviceName: F.soundcore.name))
        #expect(engine.hasActiveRoutes)
    }

    @Test func systemDefaultUnroutes() {
        let engine = makeEngine()
        engine.assign(F.soundcore, to: F.vlc.id)
        engine.assign(nil, to: F.vlc.id)
        #expect(factory.live.isEmpty)
        #expect(store.saved.isEmpty)
        #expect(engine.status(for: F.vlc.id) == .systemDefault)
    }

    @Test func failedSaveRollsBackTheWholeChange() {
        // Atomicity: if we can't persist the choice, don't apply it either.
        let engine = makeEngine()
        store.failSaves = true
        #expect(!engine.assign(F.soundcore, to: F.vlc.id))
        #expect(engine.assignments.isEmpty)
        #expect(factory.made.isEmpty)
        #expect(engine.status(for: F.vlc.id) == .failed(message: "Couldn't save your choice: Disk full"))
    }

    @Test func bluetoothDisconnectAndReconnect() {
        let engine = makeEngine()
        engine.assign(F.soundcore, to: F.vlc.id)

        system.devices = [F.speakers, F.usb]
        engine.refresh()
        #expect(factory.live.isEmpty, "route must stop so VLC falls back to the default output")
        #expect(engine.status(for: F.vlc.id) == .waitingForDevice(deviceName: F.soundcore.name))
        #expect(engine.assignments[F.vlc.id] != nil, "the choice is remembered")

        system.devices = [F.speakers, F.soundcore, F.usb]
        engine.refresh()
        #expect(factory.live.map(\.deviceUID) == [F.soundcore.uid])
    }

    @Test func routeFailureIsReportedAndRetriedAfterBackOff() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let engine = makeEngine(now: { now })
        factory.failing = [F.vlc.id]
        engine.assign(F.soundcore, to: F.vlc.id)
        #expect(engine.status(for: F.vlc.id) == .failed(message: "Could not tap app"))

        factory.failing = []
        now += 5
        engine.refresh()
        #expect(factory.live.isEmpty, "still backing off")

        now += 6
        engine.refresh()
        #expect(factory.live.count == 1)
        #expect(engine.status(for: F.vlc.id) == .routed(deviceName: F.soundcore.name))
    }

    @Test func reassigningClearsBackOffImmediately() {
        let engine = makeEngine()
        factory.failing = [F.vlc.id]
        engine.assign(F.soundcore, to: F.vlc.id)
        factory.failing = []
        engine.assign(F.usb, to: F.vlc.id)
        #expect(factory.live.map(\.deviceUID) == [F.usb.uid])
    }

    @Test func quittingStopsEveryRoute() {
        let engine = makeEngine()
        engine.assign(F.soundcore, to: F.vlc.id)
        engine.assign(F.speakers, to: F.chrome.id)
        engine.stopAll()
        #expect(factory.live.isEmpty)
        #expect(!engine.hasActiveRoutes)
        #expect(store.saved.count == 2, "choices survive a quit")
    }

    @Test func resetAllClearsChoicesAndRoutes() {
        let engine = makeEngine()
        engine.assign(F.soundcore, to: F.vlc.id)
        engine.assign(F.speakers, to: F.chrome.id)
        #expect(engine.resetAll())
        #expect(factory.live.isEmpty)
        #expect(store.saved.isEmpty)
    }

    @Test func savedChoicesAreRestoredOnLaunch() {
        store.saved = [F.vlc.id: F.assign(F.soundcore)]
        _ = makeEngine()
        #expect(factory.live.map(\.bundleID) == [F.vlc.id])
    }

    @Test func migratedDeviceNamesHealWhenDeviceIsSeen() {
        // v1.0 only stored UIDs, so migration uses the UID as the name.
        store.saved = [F.vlc.id: Assignment(deviceUID: F.soundcore.uid, deviceName: F.soundcore.uid)]
        let engine = makeEngine()
        #expect(engine.assignments[F.vlc.id]?.deviceName == F.soundcore.name)
        #expect(store.saved[F.vlc.id]?.deviceName == F.soundcore.name)
    }

    @Test func nameHealingDoesNotRewriteWhenNothingChanged() {
        store.saved = [F.vlc.id: F.assign(F.soundcore)]
        let engine = makeEngine()
        engine.refresh()
        #expect(store.saveCount == 0)
    }

    @Test func unreadableSettingsStartEmptyWithNotice() {
        store.failLoad = true
        let engine = makeEngine()
        #expect(engine.assignments.isEmpty)
        #expect(engine.notice != nil)
    }

    @Test func eachRouteIsStoppedExactlyOnce() {
        let engine = makeEngine()
        engine.assign(F.soundcore, to: F.vlc.id)
        engine.assign(F.usb, to: F.vlc.id)
        engine.stopAll()
        #expect(factory.made.allSatisfy { $0.stopCount == 1 })
    }
}
