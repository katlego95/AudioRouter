import CoreAudio
import Testing
@testable import AudioRouterCore

/// Owns a heap-allocated AudioBufferList for a test.
final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>?] = []

    /// Each entry is one buffer: channel count and interleaved samples (nil = buffer with no data).
    init(_ buffers: [(channels: Int, samples: [Float]?)]) {
        list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        for (i, b) in buffers.enumerated() {
            if let samples = b.samples {
                let p = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
                p.initialize(from: samples, count: samples.count)
                storage.append(p)
                list[i] = AudioBuffer(mNumberChannels: UInt32(b.channels),
                                      mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
                                      mData: UnsafeMutableRawPointer(p))
            } else {
                storage.append(nil)
                list[i] = AudioBuffer(mNumberChannels: UInt32(b.channels), mDataByteSize: 0, mData: nil)
            }
        }
    }

    func samples(_ index: Int) -> [Float] {
        let b = list[index]
        guard let d = b.mData else { return [] }
        let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: d.assumingMemoryBound(to: Float.self), count: n))
    }

    deinit {
        storage.forEach { $0?.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

@Suite("ChannelMixer: copies tapped audio into the device's buffers")
struct ChannelMixerTests {
    @Test func stereoToStereoCopiesSamples() {
        let input = TestBufferList([(2, [0.1, 0.2, 0.3, 0.4])])
        let output = TestBufferList([(2, [9, 9, 9, 9])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [0.1, 0.2, 0.3, 0.4])
    }

    @Test func stereoToMonoAveragesChannels() {
        let input = TestBufferList([(2, [1, 0, 0.5, 0.5])])
        let output = TestBufferList([(1, [9, 9])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [0.5, 0.5])
    }

    @Test func stereoToTwoNonInterleavedBuffers() {
        let input = TestBufferList([(2, [1, 2, 3, 4])])
        let output = TestBufferList([(1, [0, 0]), (1, [0, 0])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [1, 3])
        #expect(output.samples(1) == [2, 4])
    }

    @Test func extraOutputChannelsAreSilent() {
        let input = TestBufferList([(2, [1, 2])])
        let output = TestBufferList([(4, [9, 9, 9, 9])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [1, 2, 0, 0])
    }

    @Test func usesLastActiveInputStreamWhichIsTheTap() {
        // Aggregate inputs = [device mic (switched off), tap].
        let input = TestBufferList([(1, nil), (2, [0.7, 0.8])])
        let output = TestBufferList([(2, [0, 0])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [0.7, 0.8])
    }

    @Test func noInputProducesSilenceNotGarbage() {
        let input = TestBufferList([(2, nil)])
        let output = TestBufferList([(2, [9, 9, 9, 9])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [0, 0, 0, 0])
    }

    @Test func shorterInputLeavesTailSilent() {
        let input = TestBufferList([(2, [1, 2])])
        let output = TestBufferList([(2, [9, 9, 9, 9])])
        ChannelMixer.render(input: input.list, output: output.list)
        #expect(output.samples(0) == [1, 2, 0, 0])
    }
}

@Suite("DeviceKind")
struct DeviceKindTests {
    @Test(arguments: [
        (kAudioDeviceTransportTypeBuiltIn, DeviceKind.builtIn),
        (kAudioDeviceTransportTypeBluetooth, .bluetooth),
        (kAudioDeviceTransportTypeBluetoothLE, .bluetooth),
        (kAudioDeviceTransportTypeUSB, .usb),
        (kAudioDeviceTransportTypeAirPlay, .airPlay),
        (kAudioDeviceTransportTypeHDMI, .display),
        (kAudioDeviceTransportTypeVirtual, .virtual),
        (UInt32(0), .other),
    ])
    func mapsTransportType(transport: UInt32, kind: DeviceKind) {
        #expect(DeviceKind(transportType: transport) == kind)
    }

    @Test func everyKindHasAnIcon() {
        #expect(DeviceKind.allCases.allSatisfy { !$0.symbolName.isEmpty })
    }
}
