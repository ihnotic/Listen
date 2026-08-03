@preconcurrency import AVFoundation
import Foundation
import FluidAudio
import Speech

/// Common lifecycle for the app's selectable on-device transcription engines.
private protocol TranscriptionBackend: Actor {
    func load() async throws
    func transcribe(audioData: [Float]) async throws -> String
    func unload() async
}

/// Owns exactly one loaded backend and swaps it only after the replacement is ready.
actor TranscriptionService {
    private var backend: (any TranscriptionBackend)?
    private(set) var loadedModel: TranscriptionModel?

    func load(model: TranscriptionModel) async throws {
        if loadedModel == model, backend != nil {
            return
        }

        let nextBackend = try Self.makeBackend(for: model)
        try await nextBackend.load()

        let previousBackend = backend
        backend = nextBackend
        loadedModel = model
        await previousBackend?.unload()
    }

    func transcribe(audioData: [Float]) async throws -> String {
        guard let backend else {
            throw TranscriptionError.modelNotLoaded
        }
        return try await backend.transcribe(audioData: audioData)
    }

    private static func makeBackend(for model: TranscriptionModel) throws -> any TranscriptionBackend {
        switch model {
        case .parakeetUnifiedEnglish:
            return ParakeetUnifiedBackend()
        case .parakeetV3Multilingual:
            return ParakeetV3Backend()
        case .appleSpeechAnalyzer:
            if #available(macOS 26.0, *) {
                return AppleSpeechAnalyzerBackend()
            }
            throw TranscriptionError.unsupportedModel("Apple Speech requires macOS 26 or later.")
        }
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case unsupportedModel(String)
        case audioConversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "The transcription model is not loaded."
            case .unsupportedModel(let reason):
                return reason
            case .audioConversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            }
        }
    }
}

/// English-first Parakeet Unified offline path. The INT8 encoder is the FluidAudio default.
private actor ParakeetUnifiedBackend: TranscriptionBackend {
    private var manager: UnifiedAsrManager?

    func load() async throws {
        listenLog("ParakeetUnified: downloading/loading offline INT8 model...")
        let manager = UnifiedAsrManager(encoderPrecision: .int8)
        try await manager.loadModels()
        self.manager = manager
        listenLog("ParakeetUnified: model loaded successfully")
    }

    func transcribe(audioData: [Float]) async throws -> String {
        guard let manager else {
            throw TranscriptionService.TranscriptionError.modelNotLoaded
        }

        let samples = Self.padShortAudio(audioData)
        listenLog(
            "ParakeetUnified: transcribing \(samples.count) samples "
                + "(\(String(format: "%.1f", Float(samples.count) / 16000.0))s)..."
        )
        let text = try await manager.transcribe(samples)
        listenLog("ParakeetUnified: result = '\(text)'")
        return text
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    private static func padShortAudio(_ samples: [Float]) -> [Float] {
        let minimumSamples = 4_800 // FluidAudio supports 300 ms and longer.
        guard samples.count < minimumSamples else { return samples }
        return samples + [Float](repeating: 0, count: minimumSamples - samples.count)
    }
}

/// Existing multilingual Parakeet TDT v3 path retained for non-English dictation.
private actor ParakeetV3Backend: TranscriptionBackend {
    private var manager: AsrManager?

    func load() async throws {
        listenLog("ParakeetV3: downloading/loading multilingual model...")
        let models = try await AsrModels.downloadAndLoad(version: .v3, encoderPrecision: .int8)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        listenLog("ParakeetV3: model loaded successfully")
    }

    func transcribe(audioData: [Float]) async throws -> String {
        guard let manager else {
            throw TranscriptionService.TranscriptionError.modelNotLoaded
        }

        let samples = Self.padShortAudio(audioData)
        listenLog(
            "ParakeetV3: transcribing \(samples.count) samples "
                + "(\(String(format: "%.1f", Float(samples.count) / 16000.0))s)..."
        )
        let decoderLayerCount = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        listenLog(
            "ParakeetV3: result = '\(result.text)' "
                + "(confidence: \(String(format: "%.2f", result.confidence)), "
                + "RTFx: \(String(format: "%.0f", result.rtfx))x)"
        )
        return result.text
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    private static func padShortAudio(_ samples: [Float]) -> [Float] {
        let minimumSamples = 4_800
        guard samples.count < minimumSamples else { return samples }
        return samples + [Float](repeating: 0, count: minimumSamples - samples.count)
    }
}

/// Optional macOS 26 system backend used for side-by-side evaluation.
@available(macOS 26.0, *)
private actor AppleSpeechAnalyzerBackend: TranscriptionBackend {
    private var locale: Locale?

    func load() async throws {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionService.TranscriptionError.unsupportedModel(
                "Apple Speech is not available on this Mac."
            )
        }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "en-US")
        ) else {
            throw TranscriptionService.TranscriptionError.unsupportedModel(
                "Apple Speech does not support the en-US locale on this Mac."
            )
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)

        switch status {
        case .unsupported:
            throw TranscriptionService.TranscriptionError.unsupportedModel(
                "The Apple Speech model is unsupported on this Mac."
            )
        case .installed:
            break
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                listenLog("AppleSpeech: downloading the en-US system speech model...")
                try await request.downloadAndInstall()
            }
        @unknown default:
            throw TranscriptionService.TranscriptionError.unsupportedModel(
                "Apple Speech returned an unknown model status."
            )
        }

        locale = supportedLocale
        listenLog("AppleSpeech: en-US system model is ready")
    }

    func transcribe(audioData: [Float]) async throws -> String {
        guard let locale else {
            throw TranscriptionService.TranscriptionError.modelNotLoaded
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let modules: [any SpeechModule] = [transcriber]
        let analyzer = SpeechAnalyzer(modules: modules)
        let sourceBuffer = try Self.makeInputBuffer(samples: audioData)
        let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: sourceBuffer.format
        ) ?? sourceBuffer.format
        let analysisBuffer = try Self.convert(sourceBuffer, to: targetFormat)

        let inputSequence = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(AnalyzerInput(buffer: analysisBuffer))
            continuation.finish()
        }

        let resultTask = Task { () throws -> String in
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        do {
            try await analyzer.prepareToAnalyze(in: analysisBuffer.format)
            try await analyzer.start(inputSequence: inputSequence)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await resultTask.value
            listenLog("AppleSpeech: result = '\(text)'")
            return text
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func unload() async {
        locale = nil
        await SpeechModels.endRetention()
    }

    private static func makeInputBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?.pointee else {
            throw TranscriptionService.TranscriptionError.audioConversionFailed(
                "Could not allocate the 16 kHz mono input buffer."
            )
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private static func convert(
        _ inputBuffer: AVAudioPCMBuffer,
        to targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if inputBuffer.format == targetFormat {
            return inputBuffer
        }
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
            throw TranscriptionService.TranscriptionError.audioConversionFailed(
                "No converter is available for the Apple Speech audio format."
            )
        }

        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw TranscriptionService.TranscriptionError.audioConversionFailed(
                "Could not allocate the Apple Speech output buffer."
            )
        }

        var suppliedInput = false
        var conversionError: NSError?
        let conversionStatus = converter.convert(to: outputBuffer, error: &conversionError) {
            _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        if conversionStatus == .error {
            throw TranscriptionService.TranscriptionError.audioConversionFailed(
                conversionError?.localizedDescription ?? "The converter returned an error."
            )
        }
        return outputBuffer
    }
}
