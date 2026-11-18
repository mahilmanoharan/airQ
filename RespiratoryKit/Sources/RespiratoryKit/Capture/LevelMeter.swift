import AVFAudio
import Synchronization

/// Input level per analysis window, as an ambient-noise covariate (not an interpretation).
///
/// Samples are summarised in chunks of `chunkFrames` as they are analysed; a window's level combines
/// the chunks that start inside its frame range, so window edges resolve to one chunk (256 frames,
/// about 5 ms at 48 kHz). Written on the analysis queue and read from the SoundAnalysis callback,
/// whose thread isn't documented, hence the lock.
final class LevelMeter: Sendable {
    struct Chunk: Equatable {
        var startFrame: Int64
        var frames: Int64
        /// Sum of squared samples across all channels.
        var sumSquares: Double
        var peak: Float
        var channels: Int
    }

    static let chunkFrames: Int64 = 256
    private let retainedFrames: Int64
    private let chunks = Mutex<[Chunk]>([])

    /// Keeps about `retainSeconds` of summaries: enough for queue backlog plus a window.
    init(sampleRate: Double, retainSeconds: Double = 10) {
        retainedFrames = Int64(sampleRate * retainSeconds)
    }

    /// Summarises float PCM; other formats are not measured (the window's level is then nil).
    func ingest(_ buffer: AVAudioPCMBuffer, startFrame: Int64) {
        guard let data = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int64(buffer.frameLength)
        let stride = buffer.stride
        var summaries: [Chunk] = []
        var offset: Int64 = 0
        while offset < frames {
            let count = min(Self.chunkFrames, frames - offset)
            var sum: Double = 0
            var peak: Float = 0
            for channel in 0..<channels {
                let samples = data[channel]
                for frame in offset..<(offset + count) {
                    let sample = samples[Int(frame) * stride]
                    sum += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
            summaries.append(Chunk(startFrame: startFrame + offset, frames: count, sumSquares: sum,
                                   peak: peak, channels: channels))
            offset += count
        }
        append(summaries)
    }

    func append(_ summaries: [Chunk]) {
        guard let newest = summaries.last else { return }
        let horizon = newest.startFrame + newest.frames - retainedFrames
        chunks.withLock { stored in
            stored.append(contentsOf: summaries)
            if let firstKept = stored.firstIndex(where: { $0.startFrame >= horizon }), firstKept > 0 {
                stored.removeFirst(firstKept)
            }
        }
    }

    /// Linear RMS and peak (0...1) over chunks starting in [start, start + frames), or nil when
    /// none are retained (e.g. a format that couldn't be measured).
    func level(startFrame: Int64, frames: Int64) -> (rms: Float, peak: Float)? {
        let end = startFrame + frames
        return chunks.withLock { stored in
            var sum: Double = 0
            var samples: Int64 = 0
            var peak: Float = 0
            for chunk in stored where chunk.startFrame >= startFrame && chunk.startFrame < end {
                sum += chunk.sumSquares
                samples += chunk.frames * Int64(chunk.channels)
                peak = max(peak, chunk.peak)
            }
            guard samples > 0 else { return nil }
            return (Float((sum / Double(samples)).squareRoot()), peak)
        }
    }
}
