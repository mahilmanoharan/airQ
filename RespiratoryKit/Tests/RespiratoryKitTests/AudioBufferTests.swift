import AVFAudio
import Testing
@testable import RespiratoryKit

@Suite("Audio buffers and levels")
struct AudioBufferTests {
    private func buffer(_ samples: [Float], rate: Double = 16_000) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let data = try #require(buffer.floatChannelData)
        for (index, sample) in samples.enumerated() { data[0][index] = sample }
        return buffer
    }

    @Test("Queued audio owns its samples independently of the engine's buffer")
    func copiesSamples() throws {
        let source = try buffer([0.75, 0, 0, 0])
        let copy = try #require(AudioSlot(copying: source))
        source.floatChannelData?[0][0] = -0.5
        #expect(copy.buffer.frameLength == 4)
        #expect(copy.buffer.floatChannelData?[0][0] == 0.75)
    }

    @Test("A preallocated slot is reused for smaller buffers and refuses larger ones")
    func slotReuse() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let slot = try #require(AudioSlot(format: format, frameCapacity: 4))
        #expect(slot.copy(from: try buffer([0.1, 0.2])))
        #expect(slot.buffer.frameLength == 2 && slot.buffer.floatChannelData?[0][1] == 0.2)
        #expect(slot.copy(from: try buffer([0.3, 0.3, 0.3, 0.3])))
        #expect(slot.buffer.frameLength == 4)
        #expect(slot.copy(from: try buffer(Array(repeating: 0, count: 5))) == false)
    }

    @Test("Window levels combine the chunks that start inside the window")
    func levels() throws {
        let meter = LevelMeter(sampleRate: 16_000)
        // Two 256-frame chunks: a constant 0.5 then silence.
        meter.ingest(try buffer(Array(repeating: 0.5, count: 256) + Array(repeating: 0, count: 256)), startFrame: 0)
        let loud = try #require(meter.level(startFrame: 0, frames: 256))
        #expect(abs(loud.rms - 0.5) < 1e-6 && loud.peak == 0.5)
        let both = try #require(meter.level(startFrame: 0, frames: 512))
        #expect(abs(both.rms - Float((0.125 as Double).squareRoot())) < 1e-6)
        #expect(meter.level(startFrame: 1_000, frames: 256) == nil)
    }

    @Test("Old level summaries are dropped past the retention horizon")
    func retention() throws {
        let meter = LevelMeter(sampleRate: 1_000, retainSeconds: 1)
        meter.ingest(try buffer(Array(repeating: 0.2, count: 256), rate: 1_000), startFrame: 0)
        meter.ingest(try buffer(Array(repeating: 0.2, count: 256), rate: 1_000), startFrame: 5_000)
        #expect(meter.level(startFrame: 0, frames: 256) == nil)
        #expect(meter.level(startFrame: 5_000, frames: 256) != nil)
    }
}
