import AVFoundation
import Foundation

/// Captures microphone audio using AVAudioEngine and provides 16kHz mono Float32 samples.
final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var isRunning = false

    /// Continuation for streaming audio chunks to consumers.
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var _stream: AsyncStream<[Float]>?

    /// The target format: 16kHz mono Float32.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    private var chunkCount = 0

    /// Current audio level (RMS) — updated on every chunk from audio thread.
    var onLevel: ((Float) -> Void)?

    /// Start capturing audio. Returns an AsyncStream of Float32 chunks.
    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        listenLog("Audio input format: \(inputFormat)")
        listenLog("Audio target format: \(targetFormat)")

        // Create stream BEFORE starting the engine
        let stream = AsyncStream<[Float]> { [weak self] continuation in
            guard let self = self else { return }
            self.continuation = continuation
            self.chunkCount = 0
        }

        _stream = stream

        // Install tap with a simpler approach — convert manually
        let inputSampleRate = inputFormat.sampleRate
        let inputChannels = inputFormat.channelCount
        listenLog("Mic sample rate: \(inputSampleRate), channels: \(inputChannels)")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let continuation = self.continuation else { return }

            // Manual conversion: extract samples, convert to mono, downsample to 16kHz
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            // Get mono samples (average channels if stereo)
            var monoSamples: [Float]
            if inputChannels == 1 {
                monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                // Mix to mono
                monoSamples = [Float](repeating: 0, count: frameLength)
                for ch in 0..<Int(inputChannels) {
                    let chPtr = channelData[ch]
                    for i in 0..<frameLength {
                        monoSamples[i] += chPtr[i]
                    }
                }
                let scale = 1.0 / Float(inputChannels)
                for i in 0..<frameLength {
                    monoSamples[i] *= scale
                }
            }

            // Downsample to 16kHz using simple linear interpolation
            let ratio = inputSampleRate / 16000.0
            let outputLength = Int(Double(frameLength) / ratio)
            guard outputLength > 0 else { return }

            var resampled = [Float](repeating: 0, count: outputLength)
            for i in 0..<outputLength {
                let srcIdx = Double(i) * ratio
                let idx0 = Int(srcIdx)
                let frac = Float(srcIdx - Double(idx0))
                let idx1 = min(idx0 + 1, frameLength - 1)
                resampled[i] = monoSamples[idx0] * (1.0 - frac) + monoSamples[idx1] * frac
            }

            continuation.yield(resampled)

            // Compute RMS and send to level callback for waveform visualization
            let rms = sqrt(resampled.reduce(Float(0)) { $0 + $1 * $1 } / max(Float(resampled.count), 1))
            self.onLevel?(rms)

            self.chunkCount += 1
            if self.chunkCount == 1 {
                listenLog("First audio chunk: \(resampled.count) samples from \(frameLength) input frames")
            }
            if self.chunkCount % 100 == 0 {
                listenLog("Audio chunk #\(self.chunkCount): \(resampled.count) samples, RMS=\(String(format: "%.4f", rms))")
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        listenLog("AVAudioEngine started successfully")
    }

    /// The audio stream. Call start() first.
    var audioStream: AsyncStream<[Float]> {
        _stream ?? AsyncStream { $0.finish() }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        continuation?.finish()
        continuation = nil
        _stream = nil
        listenLog("Audio capture stopped after \(chunkCount) chunks")
    }

    enum AudioCaptureError: Error, LocalizedError {
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .converterCreationFailed:
                return "Failed to create audio format converter"
            }
        }
    }
}
