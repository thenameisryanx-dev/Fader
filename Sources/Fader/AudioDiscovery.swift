import AppKit
import CoreAudio
import Darwin

struct OutputDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

/// One Core Audio client process (an app can own several, e.g. browser helpers).
struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

enum AudioDiscovery {
    static func defaultOutputDevice() -> OutputDevice? {
        let id = CA.value(.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID.unknown)
        guard id != .unknown, let uid = CA.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let name = CA.string(id, kAudioObjectPropertyName) ?? uid
        return OutputDevice(id: id, uid: uid, name: name)
    }

    static func audioProcesses() -> [AudioProcess] {
        let ids: [AudioObjectID] = CA.array(.system, kAudioHardwarePropertyProcessObjectList)
        return ids.map { id in
            AudioProcess(
                objectID: id,
                pid: CA.value(id, kAudioProcessPropertyPID, default: pid_t(-1)),
                bundleID: CA.string(id, kAudioProcessPropertyBundleID),
                isRunningOutput: CA.value(id, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
            )
        }
    }
}

/// The user-facing app an audio process belongs to.
struct AppIdentity {
    let key: String  // bundle ID
    let name: String
    let icon: NSImage?
}

/// Maps helper processes (WebKit GPU process, Chrome helpers, ...) back to the app the user sees.
@MainActor
final class AppIdentityResolver {
    private var cache: [pid_t: AppIdentity?] = [:]

    func identity(for process: AudioProcess) -> AppIdentity? {
        if let cached = cache[process.pid] { return cached }
        let resolved = resolve(process)
        cache[process.pid] = resolved
        return resolved
    }

    func prune(keeping alive: Set<pid_t>) {
        cache = cache.filter { alive.contains($0.key) }
    }

    private func resolve(_ process: AudioProcess) -> AppIdentity? {
        var candidates = [process.pid]
        if let responsible = responsiblePID(for: process.pid), responsible != process.pid {
            candidates.append(responsible)
        }
        var pid = process.pid
        for _ in 0..<4 {
            guard let parent = parentPID(of: pid) else { break }
            candidates.append(parent)
            pid = parent
        }

        for pid in candidates {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy == .regular,
               let bundleID = app.bundleIdentifier {
                return AppIdentity(key: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
            }
        }

        // Background process with a bundle of its own, e.g. a menu bar app.
        let app = NSRunningApplication(processIdentifier: process.pid)
        guard let bundleID = app?.bundleIdentifier ?? process.bundleID else { return nil }
        let name = app?.localizedName ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return AppIdentity(key: bundleID, name: name, icon: app?.icon)
    }
}

private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

/// `responsibility_get_pid_responsible_for_pid` is what Activity Monitor uses to attribute
/// XPC helpers to their app. It is not public API, so look it up at runtime.
private let responsibilityFunction: ResponsibilityFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
        return nil
    }
    return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
}()

private func responsiblePID(for pid: pid_t) -> pid_t? {
    guard let responsibilityFunction else { return nil }
    let result = responsibilityFunction(pid)
    return result > 0 ? result : nil
}

private func parentPID(of pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let parent = info.kp_eproc.e_ppid
    return parent > 1 ? parent : nil
}
