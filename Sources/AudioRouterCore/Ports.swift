import Foundation

// "Ports" are the abstractions the engine depends on (Dependency Inversion).
// Real implementations live in AudioRouterCoreAudio; tests use in-memory fakes.

/// Reads what the system looks like right now.
@MainActor
public protocol AudioSystemProviding: AnyObject {
    func outputDevices() -> [OutputDevice]
    func defaultOutputDeviceID() -> UInt32
    func audioApps() -> [AudioApp]
}

/// A live app -> device route. Stopping it hands the app back to the system output.
@MainActor
public protocol RouteHandle: AnyObject {
    var bundleID: String { get }
    var deviceUID: String { get }
    var processIDs: [UInt32] { get }
    func stop()
}

/// Builds routes. Must be all-or-nothing: either return a fully running route,
/// or throw having released everything it created.
@MainActor
public protocol RouteFactory: AnyObject {
    func makeRoute(bundleID: String, device: OutputDevice, processIDs: [UInt32]) throws -> RouteHandle
}

/// Durable storage for the user's choices (bundle ID -> assignment).
@MainActor
public protocol AssignmentStore: AnyObject {
    func load() throws -> [String: Assignment]
    /// Must be atomic: after a crash the store holds either the old or the new value, never a mix.
    func save(_ assignments: [String: Assignment]) throws
}
