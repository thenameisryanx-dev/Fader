import Foundation

/// "System Audio Recording" permission, which process taps need.
/// There is no public API to check it, so this uses the TCC framework the way Apple's own tools do.
/// If the lookup fails the status stays `.unknown` and the system prompts on first use.
enum AudioCapturePermission {
    enum Status: Sendable { case authorized, denied, unknown }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static let preflight: PreflightFunction? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()

    private static let request: RequestFunction? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(symbol, to: RequestFunction.self)
    }()

    static var status: Status {
        guard let preflight else { return .unknown }
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(completion: @escaping @MainActor (Bool) -> Void) {
        guard let request else {
            Task { @MainActor in completion(true) }
            return
        }
        request(service, nil) { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
}

/// When to ask macOS whether Fader may record system audio. Every question is a round trip to
/// macOS's privacy service, so it's asked at most every `interval` seconds while access is
/// missing (to notice it being granted in System Settings), and not at all once it's granted.
struct PermissionCheckSchedule {
    static let interval: TimeInterval = 5

    private(set) var lastCheck: Date?

    func isDue(permission: AudioCapturePermission.Status, now: Date) -> Bool {
        guard permission != .authorized else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Self.interval
    }

    mutating func checked(at date: Date) { lastCheck = date }

    /// The permission to show after a check. `.unknown` means the lookup itself failed, so it
    /// never replaces an answer we already have.
    static func merge(
        _ current: AudioCapturePermission.Status, with answer: AudioCapturePermission.Status?
    ) -> AudioCapturePermission.Status {
        guard let answer, answer != .unknown else { return current }
        return answer
    }
}
