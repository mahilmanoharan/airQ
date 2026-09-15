import AVFAudio
import Testing
@testable import RespiratoryKit

@Suite("Audio buffer ownership")
struct AudioBufferTests {
    @Test("Queued audio owns its samples independently of the engine's buffer")
    func copiesSamples() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        source.frameLength = 4
        let samples = try #require(source.floatChannelData)
        samples[0][0] = 0.75
        let copy = try #require(CopiedAudioBuffer(source))
        samples[0][0] = -0.5
        #expect(copy.buffer.frameLength == 4)
        #expect(copy.buffer.floatChannelData?[0][0] == 0.75)
    }
}
