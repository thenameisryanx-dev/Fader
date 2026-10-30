import CoreAudio
import Testing
@testable import Fader

/// The real-time code that applies each app's volume to its audio.
/// Uses fake audio buffers, so no sound plays and no permission is needed.
struct GainRendererTests {
    @Test func fullVolumePassesAudioThroughUnchanged() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(channels: [[0.5, -0.25, 1, 0], [0.1, 0.2, -0.3, 0.4]])
        let output = AudioBuffers(channels: [[0, 0, 0, 0], [0, 0, 0, 0]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0.5, -0.25, 1, 0])
        #expect(output.channel(1) == [0.1, 0.2, -0.3, 0.4])
    }

    @Test func lowerVolumeScalesAudio() {
        let renderer = GainRenderer(gain: 0.25)
        let input = AudioBuffers(channels: [[1, -1, 0.5, 0.8]])
        let output = AudioBuffers(channels: [[0, 0, 0, 0]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0.25, -0.25, 0.125, 0.2])
    }

    @Test func muteProducesSilence() {
        let renderer = GainRenderer(gain: 0)
        let input = AudioBuffers(channels: [[1, 1, 1, 1], [1, 1, 1, 1]])
        let output = AudioBuffers(channels: [[9, 9, 9, 9], [9, 9, 9, 9]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0, 0, 0, 0])
        #expect(output.channel(1) == [0, 0, 0, 0])
    }

    /// Volume changes glide across one buffer instead of jumping, which would click.
    @Test func volumeChangeRampsSmoothly() {
        let renderer = GainRenderer(gain: 1)
        renderer.setGain(0.25)
        let input = AudioBuffers(channels: [[1, 1, 1, 1]])
        let output = AudioBuffers(channels: [[0, 0, 0, 0]])

        renderer.render(input: input.pointer, output: output.pointer)
        let ramp = output.channel(0)
        #expect(ramp == [0.8125, 0.625, 0.4375, 0.25])

        renderer.render(input: input.pointer, output: output.pointer)
        #expect(output.channel(0) == [0.25, 0.25, 0.25, 0.25])
    }

    @Test func stereoIsMixedDownForMonoOutput() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(channels: [[1, 0.5], [0, 0.5]])
        let output = AudioBuffers(channels: [[0, 0]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0.5, 0.5])
    }

    @Test func extraOutputChannelsStaySilent() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(channels: [[0.5, 0.5], [0.25, 0.25]])
        let output = AudioBuffers(channels: [[9, 9], [9, 9], [9, 9], [9, 9]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0.5, 0.5])
        #expect(output.channel(1) == [0.25, 0.25])
        #expect(output.channel(2) == [0, 0])
        #expect(output.channel(3) == [0, 0])
    }

    /// Many devices use one buffer with left/right samples alternating (interleaved).
    @Test func handlesInterleavedOutput() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(channels: [[0.1, 0.2], [0.3, 0.4]])
        let output = AudioBuffers(interleaved: [0, 0, 0, 0], channels: 2)

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.buffer(0) == [0.1, 0.3, 0.2, 0.4])
    }

    @Test func handlesInterleavedInput() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(interleaved: [0.1, 0.3, 0.2, 0.4], channels: 2)
        let output = AudioBuffers(channels: [[0, 0], [0, 0]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0.1, 0.2])
        #expect(output.channel(1) == [0.3, 0.4])
    }

    @Test func noInputMeansSilenceNotGarbage() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(channels: [])
        let output = AudioBuffers(channels: [[9, 9], [9, 9]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(output.channel(0) == [0, 0])
        #expect(output.channel(1) == [0, 0])
    }

    @Test func reportsPeakLevelOnce() {
        let renderer = GainRenderer(gain: 1)
        let input = AudioBuffers(channels: [[0.2, -0.8, 0.5]])
        let output = AudioBuffers(channels: [[0, 0, 0]])

        renderer.render(input: input.pointer, output: output.pointer)

        #expect(renderer.takePeak() == 0.8)
        #expect(renderer.takePeak() == 0)
    }

    @Test func volumeCurveEndpointsAndOrder() {
        #expect(VolumeCurve.gain(0) == 0)
        #expect(VolumeCurve.gain(1) == 1)
        let steps = stride(from: Float(0), through: 1, by: 0.05).map(VolumeCurve.gain)
        #expect(steps == steps.sorted())
    }
}

/// Fake Core Audio buffers for tests.
final class AudioBuffers {
    private let list: UnsafeMutableAudioBufferListPointer

    /// One buffer per channel (non-interleaved).
    init(channels: [[Float]]) {
        list = AudioBufferList.allocate(maximumBuffers: max(channels.count, 1))
        list.count = channels.count
        for (index, samples) in channels.enumerated() {
            list[index] = Self.makeBuffer(samples, channels: 1)
        }
    }

    /// One buffer with the channels' samples alternating.
    init(interleaved samples: [Float], channels: Int) {
        list = AudioBufferList.allocate(maximumBuffers: 1)
        list[0] = Self.makeBuffer(samples, channels: channels)
    }

    deinit {
        for buffer in list { buffer.mData?.deallocate() }
        free(list.unsafeMutablePointer)
    }

    var pointer: UnsafeMutablePointer<AudioBufferList> { list.unsafeMutablePointer }

    func channel(_ index: Int) -> [Float] { buffer(index) }

    func buffer(_ index: Int) -> [Float] {
        let buffer = list[index]
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let data = buffer.mData!.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: data, count: count))
    }

    private static func makeBuffer(_ samples: [Float], channels: Int) -> AudioBuffer {
        let data = UnsafeMutablePointer<Float>.allocate(capacity: max(samples.count, 1))
        data.initialize(from: samples, count: samples.count)
        return AudioBuffer(
            mNumberChannels: UInt32(channels),
            mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(data)
        )
    }
}
