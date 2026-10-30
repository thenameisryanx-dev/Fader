import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String { "\(operation) failed with \(status.fourCharCode)" }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
}

extension OSStatus {
    /// Core Audio errors are usually four-character codes like 'who?'.
    var fourCharCode: String {
        let n = UInt32(bitPattern: self)
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((n >> $0) & 0xFF))) }
        let text = String(chars)
        return text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "?" || $0 == "!" })
            ? "'\(text)'" : "\(self)"
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)
}

/// Thin wrappers over AudioObjectGetPropertyData.
enum CA {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        default fallback: T
    ) -> T {
        var addr = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        var result = fallback
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? result : fallback
    }

    static func array<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [T] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<T>.stride
        return [T](unsafeUninitializedCapacity: capacity) { buffer, initialized in
            let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, buffer.baseAddress!)
            initialized = status == noErr ? Int(size) / MemoryLayout<T>.stride : 0
        }
    }

    static func string(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var addr = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var ref: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    /// Whether the object has this property and it can be changed.
    static func isSettable(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> Bool {
        var addr = address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &addr, &settable) == noErr && settable.boolValue
    }

    @discardableResult
    static func set<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ value: T
    ) -> Bool {
        var addr = address(selector, scope: scope)
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: value) {
            AudioObjectSetPropertyData(object, &addr, 0, nil, size, $0) == noErr
        }
    }
}

/// Registers a Core Audio property listener for as long as the object is alive.
final class PropertyListener {
    private let object: AudioObjectID
    private var addr: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        handler: @escaping @MainActor () -> Void
    ) {
        self.object = object
        self.addr = CA.address(selector, scope: scope)
        self.block = { _, _ in MainActor.assumeIsolated { handler() } }
        AudioObjectAddPropertyListenerBlock(object, &addr, .main, block)
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(object, &addr, .main, block)
    }
}
