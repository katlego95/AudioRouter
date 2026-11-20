import Foundation

/// A route that is currently running.
public struct ActiveRoute: Hashable, Sendable {
    public let bundleID: String
    public let deviceUID: String
    public let processIDs: [UInt32]

    public init(bundleID: String, deviceUID: String, processIDs: [UInt32]) {
        self.bundleID = bundleID
        self.deviceUID = deviceUID
        self.processIDs = processIDs
    }
}

/// A route that should be started.
public struct RouteStart: Hashable, Sendable {
    public let bundleID: String
    public let device: OutputDevice
    public let processIDs: [UInt32]

    public init(bundleID: String, device: OutputDevice, processIDs: [UInt32]) {
        self.bundleID = bundleID
        self.device = device
        self.processIDs = processIDs
    }
}

/// The changes needed to make live routes match the user's choices. Stops run before starts.
public struct RoutePlan: Equatable, Sendable {
    public var stops: [String]
    public var starts: [RouteStart]

    public init(stops: [String], starts: [RouteStart]) {
        self.stops = stops
        self.starts = starts
    }
}

/// Pure routing policy: given the world and the user's choices, what must change?
/// No side effects, so it is exhaustively unit-tested (see RoutePlannerTests).
public struct RoutePlanner: Sendable {
    /// After a failed attempt, wait this long before retrying automatically.
    public var retryDelay: TimeInterval

    public init(retryDelay: TimeInterval = 10) {
        self.retryDelay = retryDelay
    }

    public func plan(active: [ActiveRoute],
                     assignments: [String: Assignment],
                     apps: [AudioApp],
                     devices: [OutputDevice],
                     lastFailure: [String: Date],
                     now: Date) -> RoutePlan {
        let appsByID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let devicesByUID = Dictionary(devices.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })

        // A route stays only if it still matches exactly what is wanted.
        var stops: [String] = []
        var kept: Set<String> = []
        for route in active {
            let stillValid = assignments[route.bundleID]?.deviceUID == route.deviceUID
                && devicesByUID[route.deviceUID] != nil
                && appsByID[route.bundleID]?.processIDs == route.processIDs
            if stillValid { kept.insert(route.bundleID) } else { stops.append(route.bundleID) }
        }

        var starts: [RouteStart] = []
        for (bundleID, assignment) in assignments where !kept.contains(bundleID) {
            guard let app = appsByID[bundleID], let device = devicesByUID[assignment.deviceUID] else { continue }
            if let failed = lastFailure[bundleID], now.timeIntervalSince(failed) < retryDelay { continue }
            starts.append(RouteStart(bundleID: bundleID, device: device, processIDs: app.processIDs))
        }

        return RoutePlan(stops: stops.sorted(), starts: starts.sorted { $0.bundleID < $1.bundleID })
    }
}

extension RouteStatus {
    /// Derives what to show for one app. Errors win, then live routes, then device presence.
    public static func resolve(bundleID: String,
                               assignments: [String: Assignment],
                               activeDeviceUIDs: [String: String],
                               devices: [OutputDevice],
                               errors: [String: String]) -> RouteStatus {
        if let message = errors[bundleID] { return .failed(message: message) }
        guard let assignment = assignments[bundleID] else { return .systemDefault }
        guard let device = devices.first(where: { $0.uid == assignment.deviceUID }) else {
            return .waitingForDevice(deviceName: assignment.deviceName)
        }
        if activeDeviceUIDs[bundleID] == assignment.deviceUID {
            return .routed(deviceName: device.name)
        }
        return .connecting(deviceName: device.name)
    }
}
