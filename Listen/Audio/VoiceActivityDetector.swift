import Foundation

/// RMS energy-based voice activity detector.
/// Ported from listen/audio.py — segments audio based on energy thresholds.
final class VoiceActivityDetector {
    var energyThreshold: Float = 0.002
    var minSpeechMs: Int = 250
    var minSilenceMs: Int = 700

    private var segmentBuffer: [Float] = []
    private var silenceDurationMs: Float = 0
    private var speechDetected = false
    private let sampleRate: Float = 16000

    /// Continuation for yielding complete speech segments.
    private var continuation: AsyncStream<[Float]>.Continuation?

    private var chunkCount = 0
    private var speechChunks = 0
    private var silenceChunks = 0

    /// Process audio from the capture service and yield speech segments.
    func processAudio(from captureService: AudioCaptureService) -> AsyncStream<[Float]> {
        resetState()

        return AsyncStream { continuation in
            self.continuation = continuation

            Task {
                listenLog("VAD: starting to process audio stream")
                for await chunk in captureService.audioStream {
                    self.processChunk(chunk)
                }
                // Flush any remaining audio when stream ends
                listenLog("VAD: audio stream ended, flushing remaining buffer (\(self.segmentBuffer.count) samples)")
                self.flushSegment()
                continuation.finish()
                listenLog("VAD: stream finished")
            }
        }
    }

    /// Process a single audio chunk.
    private func processChunk(_ chunk: [Float]) {
        let rms = Self.computeRMS(chunk)
        let isSpeech = rms > energyThreshold
        let chunkDurationMs = Float(chunk.count) / sampleRate * 1000

        chunkCount += 1

        if chunkCount <= 3 {
            listenLog("VAD chunk #\(chunkCount): \(chunk.count) samples, RMS=\(String(format: "%.5f", rms)), threshold=\(energyThreshold), isSpeech=\(isSpeech)")
        }

        if isSpeech {
            segmentBuffer.append(contentsOf: chunk)
            silenceDurationMs = 0
            if !speechDetected {
                listenLog("VAD: speech started (RMS=\(String(format: "%.4f", rms)))")
            }
            speechDetected = true
            speechChunks += 1
        } else if speechDetected {
            // Include trailing silence in segment
            segmentBuffer.append(contentsOf: chunk)
            silenceDurationMs += chunkDurationMs
            silenceChunks += 1

            if silenceDurationMs >= Float(minSilenceMs) {
                listenLog("VAD: silence threshold reached (\(String(format: "%.0f", silenceDurationMs))ms >= \(minSilenceMs)ms)")
                yieldSegmentIfValid()
            }
        }

        // Log periodic stats
        if chunkCount % 200 == 0 {
            listenLog("VAD stats: \(chunkCount) chunks, \(speechChunks) speech, \(silenceChunks) silence, buffer=\(segmentBuffer.count) samples, RMS=\(String(format: "%.5f", rms))")
        }
    }

    /// Flush any buffered audio as a segment (called when recording stops).
    func flush() {
        listenLog("VAD: flush called, speechDetected=\(speechDetected), buffer=\(segmentBuffer.count) samples")
        flushSegment()
    }

    private func flushSegment() {
        if !segmentBuffer.isEmpty {
            // Always yield remaining buffer on flush, even if below min speech duration
            let durationMs = Float(segmentBuffer.count) / sampleRate * 1000
            if durationMs >= Float(minSpeechMs) {
                let segment = segmentBuffer
                listenLog("VAD: yielding flushed segment: \(segment.count) samples (\(String(format: "%.1f", durationMs))ms)")
                continuation?.yield(segment)
            } else {
                listenLog("VAD: discarding short flushed segment: \(segmentBuffer.count) samples (\(String(format: "%.1f", durationMs))ms < \(minSpeechMs)ms)")
            }
        }
        resetState()
    }

    private func yieldSegmentIfValid() {
        let durationMs = Float(segmentBuffer.count) / sampleRate * 1000
        if durationMs >= Float(minSpeechMs) {
            let segment = segmentBuffer
            listenLog("VAD: yielding segment: \(segment.count) samples (\(String(format: "%.1f", durationMs))ms)")
            continuation?.yield(segment)
        } else {
            listenLog("VAD: discarding short segment: \(segmentBuffer.count) samples (\(String(format: "%.1f", durationMs))ms < \(minSpeechMs)ms)")
        }
        segmentBuffer = []
        silenceDurationMs = 0
        speechDetected = false
    }

    private func resetState() {
        segmentBuffer = []
        silenceDurationMs = 0
        speechDetected = false
        chunkCount = 0
        speechChunks = 0
        silenceChunks = 0
    }

    /// Compute RMS (root mean square) energy of audio samples.
    static func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }
}
