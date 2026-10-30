import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// Takes over one app's audio: a process tap mutes the app's own output and captures it,
/// and a private aggregate device plays it back on the real output device with our gain applied.
final class AppTap {
    let processIDs: Set<AudioObjectID>
    let deviceUID: String

    private let renderer: GainRenderer
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    init(appName: String, processIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        self.processIDs = Set(processIDs)
        self.deviceUID = outputDeviceUID
        self.renderer = GainRenderer(gain: gain)
        do {
            try start(appName: appName)
        } catch {
            // Never leave a tap behind: with .mutedWhenTapped it would silence the app.
            invalidate()
            throw error
        }
    }

    deinit { invalidate() }

    func setGain(_ gain: Float) { renderer.setGain(gain) }

    /// Highest input sample level since the last call.
    func takePeak() -> Float { renderer.takePeak() }

    func invalidate() {
        if aggregateID != .unknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = .unknown
        tapID = .unknown
    }

    private func start(appName: String) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: Array(processIDs))
        description.uuid = UUID()
        description.name = "Fader – \(appName)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")

        let format = CA.value(tapID, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            throw CoreAudioError(operation: "Unsupported tap format", status: OSStatus(format.mFormatID))
        }

        let tapUID = CA.string(tapID, kAudioTapPropertyUID) ?? description.uuid.uuidString
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fader – \(appName)",
            kAudioAggregateDeviceUIDKey: "com.ryan.Fader.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice"
        )

        let renderer = self.renderer
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                renderer.render(input: input, output: output)
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }
}

/// Runs on the real-time IO thread: no locks, no allocation.
final class GainRenderer: @unchecked Sendable {
    private let targetBits: Atomic<UInt32>
    private let peakBits = Atomic<UInt32>(0)
    private var current: Float

    init(gain: Float) {
        targetBits = Atomic(gain.bitPattern)
        current = gain
    }

    func setGain(_ gain: Float) {
        targetBits.store(gain.bitPattern, ordering: .relaxed)
    }

    func takePeak() -> Float {
        Float(bitPattern: peakBits.exchange(0, ordering: .relaxed))
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }

        let target = Float(bitPattern: targetBits.load(ordering: .relaxed))
        let inChannels = channelCount(inputs)
        let outChannels = channelCount(outputs)
        let frames = min(frameCount(inputs), frameCount(outputs))
        guard inChannels > 0, outChannels > 0, frames > 0 else {
            current = target
            return
        }

        // Ramp across the buffer so gain changes don't click.
        let start = current
        let step = (target - start) / Float(frames)
        var peak: Float = 0

        for outChannel in 0..<outChannels {
            guard let (out, outStride) = channel(outputs, outChannel) else { continue }
            if outChannels == 1, inChannels >= 2,
               let (left, leftStride) = channel(inputs, 0), let (right, rightStride) = channel(inputs, 1) {
                var gain = start
                for frame in 0..<frames {
                    gain += step
                    let sample = 0.5 * (left[frame * leftStride] + right[frame * rightStride])
                    peak = max(peak, abs(sample))
                    out[frame * outStride] = sample * gain
                }
            } else if outChannel < inChannels, let (source, sourceStride) = channel(inputs, outChannel) {
                var gain = start
                for frame in 0..<frames {
                    gain += step
                    let sample = source[frame * sourceStride]
                    peak = max(peak, abs(sample))
                    out[frame * outStride] = sample * gain
                }
            }
        }

        current = target
        if peak > Float(bitPattern: peakBits.load(ordering: .relaxed)) {
            peakBits.store(peak.bitPattern, ordering: .relaxed)
        }
    }

    @inline(__always)
    private func channelCount(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
        list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    @inline(__always)
    private func frameCount(_ list: UnsafeMutableAudioBufferListPointer) -> Int {
        guard let first = list.first, first.mNumberChannels > 0 else { return 0 }
        return Int(first.mDataByteSize) / (MemoryLayout<Float>.size * Int(first.mNumberChannels))
    }

    /// Pointer to the first sample of a channel plus the stride between its samples,
    /// covering both interleaved and non-interleaved buffer lists.
    @inline(__always)
    private func channel(_ list: UnsafeMutableAudioBufferListPointer, _ index: Int) -> (UnsafeMutablePointer<Float>, Int)? {
        var remaining = index
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            if remaining < channels {
                guard let data = buffer.mData else { return nil }
                return (data.assumingMemoryBound(to: Float.self) + remaining, channels)
            }
            remaining -= channels
        }
        return nil
    }
}
