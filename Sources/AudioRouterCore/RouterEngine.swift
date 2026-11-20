import Foundation
import Combine

/// The app's single source of truth. Owns live routes and keeps them in line with the
/// user's choices as apps start/stop and devices come and go.
///
/// Depends only on the ports in `Ports.swift`, so it runs identically against real
/// Core Audio or against the fakes in the test suite.
///
/// Isolation: everything runs on the main actor. The real-time audio thread never
/// touches this object; it only runs `ChannelMixer`.
@MainActor
public final class RouterEngine: ObservableObject {
    @Published public private(set) var apps: [AudioApp] = []
    @Published public private(set) var devices: [OutputDevice] = []
    @Published public private(set) var defaultDevice: OutputDevice?
    @Published public private(set) var assignments: [String: Assignment] = [:]
    @Published public private(set) var errors: [String: String] = [:]
    /// bundle ID -> device UID of each running route.
    @Published public private(set) var activeDeviceUIDs: [String: String] = [:]
    /// One-off message for the user (e.g. settings had to be reset).
    @Published public var notice: String?

    private let system: AudioSystemProviding
    private let factory: RouteFactory
    private let store: AssignmentStore
    private let planner: RoutePlanner
    private let now: @MainActor () -> Date

    private var routes: [String: RouteHandle] = [:]
    private var lastFailure: [String: Date] = [:]
    private var timer: Timer?

    public init(system: AudioSystemProviding,
                factory: RouteFactory,
                store: AssignmentStore,
                planner: RoutePlanner = RoutePlanner(),
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.system = system
        self.factory = factory
        self.store = store
        self.planner = planner
        self.now = now
        do {
            assignments = try store.load()
        } catch {
            notice = error.localizedDescription
        }
        refresh()
    }

    // MARK: Queries

    public var hasActiveRoutes: Bool { !routes.isEmpty }

    public func status(for bundleID: String) -> RouteStatus {
        .resolve(bundleID: bundleID, assignments: assignments, activeDeviceUIDs: activeDeviceUIDs,
                 devices: devices, errors: errors)
    }

    // MARK: Commands

    /// Sends an app to `device`, or back to the system output when `device` is nil.
    ///
    /// Transactional: the choice is saved first; if saving fails nothing changes.
    @discardableResult
    public func assign(_ device: OutputDevice?, to bundleID: String) -> Bool {
        var next = assignments
        if let device {
            next[bundleID] = Assignment(deviceUID: device.uid, deviceName: device.name)
        } else {
            next.removeValue(forKey: bundleID)
        }
        do {
            try store.save(next)
        } catch {
            errors[bundleID] = "Couldn't save your choice: \(error.localizedDescription)"
            return false
        }
        assignments = next
        errors[bundleID] = nil
        lastFailure[bundleID] = nil
        reconcile()
        return true
    }

    /// Sends every app back to the system output.
    @discardableResult
    public func resetAll() -> Bool {
        do {
            try store.save([:])
        } catch {
            notice = "Couldn't reset: \(error.localizedDescription)"
            return false
        }
        assignments = [:]
        errors = [:]
        lastFailure = [:]
        reconcile()
        return true
    }

    /// Re-reads apps and devices, then repairs routes.
    public func refresh() {
        let newDevices = system.outputDevices()
        if newDevices != devices { devices = newDevices }
        let defaultID = system.defaultOutputDeviceID()
        let newDefault = newDevices.first { $0.id == defaultID }
        if newDefault != defaultDevice { defaultDevice = newDefault }
        let newApps = system.audioApps()
        if newApps != apps { apps = newApps }
        healDeviceNames()
        reconcile()
    }

    /// Keeps saved device names current (renamed devices, or UIDs migrated from v1.0),
    /// so "Waiting for …" shows a real name. Best effort: a failed save changes nothing.
    private func healDeviceNames() {
        var next = assignments
        for (bundleID, assignment) in assignments {
            if let device = devices.first(where: { $0.uid == assignment.deviceUID }), device.name != assignment.deviceName {
                next[bundleID]?.deviceName = device.name
            }
        }
        guard next != assignments, (try? store.save(next)) != nil else { return }
        assignments = next
    }

    /// Stops all routes (apps return to the system output). Choices are kept.
    public func stopAll() {
        timer?.invalidate()
        timer = nil
        for route in routes.values { route.stop() }
        routes.removeAll()
        publishActiveRoutes()
    }

    /// Polls for app/device changes.
    public func startPolling(every interval: TimeInterval = 1.5) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Reconciliation

    private func reconcile() {
        let active = routes.values.map {
            ActiveRoute(bundleID: $0.bundleID, deviceUID: $0.deviceUID, processIDs: $0.processIDs)
        }
        let plan = planner.plan(active: active, assignments: assignments, apps: apps, devices: devices,
                                lastFailure: lastFailure, now: now())

        for bundleID in plan.stops {
            routes.removeValue(forKey: bundleID)?.stop()
        }
        for start in plan.starts {
            do {
                routes[start.bundleID] = try factory.makeRoute(bundleID: start.bundleID, device: start.device,
                                                               processIDs: start.processIDs)
                if errors[start.bundleID] != nil { errors[start.bundleID] = nil }
                lastFailure[start.bundleID] = nil
            } catch {
                errors[start.bundleID] = error.localizedDescription
                lastFailure[start.bundleID] = now()
            }
        }
        publishActiveRoutes()
    }

    private func publishActiveRoutes() {
        let snapshot = routes.mapValues(\.deviceUID)
        if snapshot != activeDeviceUIDs { activeDeviceUIDs = snapshot }
    }
}
