import CoreAudio
import AudioRouterCore

let kSystemObject = AudioObjectID(kAudioObjectSystemObject)
let kUnknownObject = AudioObjectID(kAudioObjectUnknown)

/// A failed Core Audio call, with a human-readable step.
public struct CoreAudioError: LocalizedError {
    public let step: String
    public let status: OSStatus
    public var errorDescription: String? { "Could not \(step) (error \(status))" }
}

func check(_ status: OSStatus, _ step: @autoclosure () -> String) throws {
    if status != noErr { throw CoreAudioError(step: step(), status: status) }
}

/// Thin, typed wrappers over `AudioObjectGetPropertyData`.
enum CAProperty {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func array<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         of _: T.Type) -> [T] {
        var addr = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        return Array(UnsafeBufferPointer(start: raw.bindMemory(to: T.self, capacity: count), count: count))
    }

    static func scalar<T: BitwiseCopyable>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                           default fallback: T) -> T {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        var value = fallback
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? value : fallback
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }
}
