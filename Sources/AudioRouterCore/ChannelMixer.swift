import CoreAudio

/// Copies tapped audio (Float32) into a device's output buffers.
///
/// Runs on the real-time audio thread: no allocation, no locks, no Swift arrays.
public enum ChannelMixer {
    public static func render(input: UnsafeMutableAudioBufferListPointer,
                              output: UnsafeMutableAudioBufferListPointer) {
        var totalOut = 0
        for buf in output {
            if let d = buf.mData { memset(d, 0, Int(buf.mDataByteSize)) }
            totalOut += Int(buf.mNumberChannels)
        }

        // The tap is the last active input stream of the aggregate device
        // (the device's own mic streams come first and are switched off).
        var source: AudioBuffer?
        for buf in input where buf.mData != nil && buf.mDataByteSize > 0 { source = buf }
        guard let src = source, let srcData = src.mData else { return }

        let inCh = max(Int(src.mNumberChannels), 1)
        let inFrames = Int(src.mDataByteSize) / (MemoryLayout<Float>.size * inCh)
        let s = srcData.assumingMemoryBound(to: Float.self)
        let downmixToMono = totalOut == 1 && inCh >= 2

        var base = 0
        for buf in output {
            let ch = max(Int(buf.mNumberChannels), 1)
            defer { base += ch }
            guard let d = buf.mData else { continue }
            let o = d.assumingMemoryBound(to: Float.self)
            let frames = min(inFrames, Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * ch))
            for f in 0..<frames {
                let frame = f * inCh
                for c in 0..<ch {
                    let g = base + c
                    if downmixToMono {
                        o[f * ch + c] = (s[frame] + s[frame + 1]) * 0.5
                    } else if g < inCh {
                        o[f * ch + c] = s[frame + g]
                    }
                }
            }
        }
    }
}
