import Foundation
import CoreAudio

/// What kind of hardware an output is. Drives the icon shown in the UI.
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case builtIn, bluetooth, usb, airPlay, display, virtual, other

    /// Maps a Core Audio transport type (`kAudioDevicePropertyTransportType`) to a kind.
    public init(transportType: UInt32) {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeThunderbolt: self = .display
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate: self = .virtual
        default: self = .other
        }
    }

    /// SF Symbol for this kind of device.
    public var symbolName: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "headphones"
        case .usb: "cable.connector"
        case .airPlay: "airplayaudio"
        case .display: "tv"
        case .virtual: "waveform.circle"
        case .other: "hifispeaker"
        }
    }
}

/// A device that can play sound.
public struct OutputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio object ID. Changes across reboots/reconnects, so never persist it.
    public let id: UInt32
    /// Stable identifier. This is what gets saved.
    public let uid: String
    public let name: String
    public let kind: DeviceKind

    public init(id: UInt32, uid: String, name: String, kind: DeviceKind = .other) {
        self.id = id
        self.uid = uid
        self.name = name
        self.kind = kind
    }
}

/// An app (grouped with its helper processes) that has an audio session.
public struct AudioApp: Identifiable, Hashable, Sendable {
    /// Bundle identifier.
    public let id: String
    public let name: String
    public let bundleURL: URL?
    /// Core Audio process object IDs (not PIDs) owned by this app, sorted.
    public var processIDs: [UInt32]
    public var isPlaying: Bool

    public init(id: String, name: String, bundleURL: URL? = nil, processIDs: [UInt32], isPlaying: Bool) {
        self.id = id
        self.name = name
        self.bundleURL = bundleURL
        self.processIDs = processIDs
        self.isPlaying = isPlaying
    }
}

/// The user's choice for one app. The device name is kept so the UI can say
/// "Waiting for soundcore Select 4 Go" while that speaker is disconnected.
public struct Assignment: Codable, Hashable, Sendable {
    public var deviceUID: String
    public var deviceName: String

    public init(deviceUID: String, deviceName: String) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
    }
}

/// What the UI should say about an app.
public enum RouteStatus: Equatable, Sendable {
    /// No choice made: the app follows the system output.
    case systemDefault
    /// Audio is flowing to the chosen device.
    case routed(deviceName: String)
    /// Chosen device is present but the route hasn't started yet (e.g. retry back-off).
    case connecting(deviceName: String)
    /// Chosen device is disconnected; the app is playing on the system output meanwhile.
    case waitingForDevice(deviceName: String)
    /// The last attempt to route failed.
    case failed(message: String)
}
