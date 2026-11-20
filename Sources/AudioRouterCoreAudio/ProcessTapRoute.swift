import CoreAudio
import AudioToolbox
import AudioRouterCore

/// Builds real routes with Core Audio process taps.
@MainActor
public final class ProcessTapRouteFactory: RouteFactory {
    public init() {}

    public func makeRoute(bundleID: String, device: OutputDevice, processIDs: [UInt32]) throws -> RouteHandle {
        try ProcessTapRoute(bundleID: bundleID, device: device, processIDs: processIDs)
    }
}

/// Taps an app's audio (muting it on the system output) and plays it on another device
/// through a private aggregate device:
///
///     app ──tap (muted when tapped)──▶ aggregate[device + tap] ──IOProc──▶ device speakers
///
/// Atomic: `init` either returns a running route or throws after releasing everything it made.
@MainActor
final class ProcessTapRoute: RouteHandle {
    let bundleID: String
    let deviceUID: String
    let processIDs: [UInt32]

    private var tapID = kUnknownObject
    private var aggregateID = kUnknownObject
    private var procID: AudioDeviceIOProcID?

    init(bundleID: String, device: OutputDevice, processIDs: [UInt32]) throws {
        self.bundleID = bundleID
        self.deviceUID = device.uid
        self.processIDs = processIDs
        do {
            try start(device: device)
        } catch {
            stop() // roll back whatever was created
            throw error
        }
    }

    private func start(device: OutputDevice) throws {
        // 1. Tap the app. "mutedWhenTapped" silences it on the normal output only while the
        //    tap is being read, so if anything below fails the app keeps playing as normal.
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: processIDs)
        tapDesc.uuid = UUID()
        tapDesc.name = "AudioRouter \(bundleID)"
        tapDesc.muteBehavior = .mutedWhenTapped
        var tap = kUnknownObject
        try check(AudioHardwareCreateProcessTap(tapDesc, &tap), "tap \(bundleID)")
        tapID = tap

        // 2. Private aggregate device: target output (clock source) + the tap as input.
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter \(bundleID)",
            kAudioAggregateDeviceUIDKey: CoreAudioSystem.ownDevicePrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: device.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapDesc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var agg = kUnknownObject
        try check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg), "create output for \(device.name)")
        aggregateID = agg

        // 3. Real-time callback: copy tapped audio into the device's output buffers.
        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, agg, nil, Self.makeIOBlock()), "start audio callback")
        procID = proc

        // 4. Keep the device's own microphone streams off, so Bluetooth headsets stay in
        //    high-quality playback mode instead of switching to headset (call) mode.
        let micStreams = CAProperty.array(device.id, kAudioDevicePropertyStreams,
                                          scope: kAudioObjectPropertyScopeInput, of: AudioStreamID.self).count
        disableInputStreams(count: micStreams)

        try check(AudioDeviceStart(agg, proc), "start playback on \(device.name)")
    }

    /// Built outside the main actor on purpose: the HAL calls this block on its real-time
    /// thread, and a main-actor-isolated closure would trip Swift's runtime isolation check.
    private nonisolated static func makeIOBlock() -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            ChannelMixer.render(input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                                output: UnsafeMutableAudioBufferListPointer(output))
        }
    }

    private func disableInputStreams(count: Int) {
        guard count > 0, let procID else { return }
        var addr = CAProperty.address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &addr, 0, nil, &size) == noErr, size > 0 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        memset(raw, 0, Int(size))
        let usage = raw.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
        usage.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, raw) == noErr else { return }
        let total = Int(usage.pointee.mNumberStreams)
        guard total > count else { return } // never switch off the tap stream (always last)
        let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
        let flags = (raw + offset).assumingMemoryBound(to: UInt32.self)
        for i in 0..<count { flags[i] = 0 }
        _ = AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, size, raw)
    }

    /// Idempotent. After this the app plays on the system output again.
    func stop() {
        if aggregateID != kUnknownObject {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kUnknownObject {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = kUnknownObject
        tapID = kUnknownObject
    }
}
