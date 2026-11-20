import AppKit
import CoreAudio
import AudioRouterCore

/// Reads devices and audio-using apps from the Core Audio HAL.
@MainActor
public final class CoreAudioSystem: AudioSystemProviding {
    /// Aggregate devices we create are named with this prefix and hidden from the device list.
    static let ownDevicePrefix = "AudioRouter-"

    public init() {}

    public func outputDevices() -> [OutputDevice] {
        CAProperty.array(kSystemObject, kAudioHardwarePropertyDevices, of: AudioObjectID.self).compactMap { id in
            let outStreams = CAProperty.array(id, kAudioDevicePropertyStreams,
                                              scope: kAudioObjectPropertyScopeOutput, of: AudioStreamID.self)
            guard !outStreams.isEmpty,
                  let uid = CAProperty.string(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(Self.ownDevicePrefix),
                  let name = CAProperty.string(id, kAudioObjectPropertyName) else { return nil }
            let transport = CAProperty.scalar(id, kAudioDevicePropertyTransportType, default: UInt32(0))
            return OutputDevice(id: id, uid: uid, name: name, kind: DeviceKind(transportType: transport))
        }
    }

    public func defaultOutputDeviceID() -> UInt32 {
        CAProperty.scalar(kSystemObject, kAudioHardwarePropertyDefaultOutputDevice, default: kUnknownObject)
    }

    public func audioApps() -> [AudioApp] {
        let me = ProcessInfo.processInfo.processIdentifier
        var groups: [String: AudioApp] = [:]
        for obj in CAProperty.array(kSystemObject, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self) {
            let pid = CAProperty.scalar(obj, kAudioProcessPropertyPID, default: pid_t(-1))
            guard pid > 0, pid != me,
                  let app = ProcessOwnership.owningApp(of: pid),
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { continue }
            let playing = CAProperty.scalar(obj, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
            var entry = groups[bundleID] ?? AudioApp(id: bundleID, name: app.localizedName ?? bundleID,
                                                     bundleURL: app.bundleURL, processIDs: [], isPlaying: false)
            entry.processIDs.append(obj)
            entry.isPlaying = entry.isPlaying || playing
            groups[bundleID] = entry
        }
        return groups.values
            .map { var a = $0; a.processIDs.sort(); return a }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Maps helper processes (Chrome Helper, WebKit GPU process, ...) to the app that owns them.
enum ProcessOwnership {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    @MainActor
    static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        let responsible = responsibleFn?(pid) ?? pid
        for candidate in [responsible, pid] where candidate > 0 {
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy == .regular {
                return app
            }
        }
        // Fallback: the outermost .app in the executable path.
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        let path = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard let r = path.range(of: ".app/") else { return nil }
        let appPath = String(path[..<r.lowerBound]) + ".app"
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.path == appPath && $0.activationPolicy == .regular
        }
    }
}
