import Foundation
import FluidAudio

/// Wraps FluidAudio (Parakeet TDT 0.6B) for speech-to-text transcription.
/// Uses NVIDIA's Parakeet model via CoreML on Apple Neural Engine.
final class WhisperService {
    private var asrManager: AsrManager?

    /// Download (if needed) and load the Parakeet model.
    func loadModel(path: String) async throws {
        listenLog("ParakeetService: downloading/loading Parakeet TDT 0.6B v3 model...")

        // FluidAudio auto-downloads from HuggingFace and caches locally
        let models = try await AsrModels.downloadAndLoad(version: .v3)

        let asr = AsrManager(config: .default)
        try await asr.initialize(models: models)
        asrManager = asr

        listenLog("ParakeetService: model loaded successfully!")
    }

    /// Minimum samples required by Parakeet (1 second at 16kHz).
    private let minSamples = 16000

    /// Transcribe 16kHz mono Float32 audio data to text.
    func transcribe(audioData: [Float]) async throws -> String {
        guard let asr = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        // Pad short segments with silence so Parakeet doesn't reject them
        var samples = audioData
        if samples.count < minSamples {
            listenLog("ParakeetService: padding \(samples.count) samples to \(minSamples) minimum")
            samples.append(contentsOf: [Float](repeating: 0, count: minSamples - samples.count))
        }

        listenLog("ParakeetService: transcribing \(samples.count) samples (\(String(format: "%.1f", Float(samples.count) / 16000.0))s)...")
        let result = try await asr.transcribe(samples, source: .microphone)
        listenLog("ParakeetService: result = '\(result.text)' (confidence: \(String(format: "%.2f", result.confidence)), RTFx: \(String(format: "%.0f", result.rtfx))x)")
        return result.text
    }

    var isLoaded: Bool {
        asrManager != nil
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            "Parakeet model is not loaded"
        }
    }
}
