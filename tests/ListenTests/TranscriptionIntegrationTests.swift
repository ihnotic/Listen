import AVFoundation
import XCTest
@testable import Listen

final class TranscriptionIntegrationTests: XCTestCase {
    func testUnifiedModelTranscribesKnownSpeech() async throws {
        let samples = try integrationSamples()
        try await assertKnownSpeech(using: .parakeetUnifiedEnglish, samples: samples)
    }

    func testMultilingualModelTranscribesKnownSpeech() async throws {
        let samples = try integrationSamples()
        try await assertKnownSpeech(using: .parakeetV3Multilingual, samples: samples)
    }

    func testAppleSpeechAnalyzerTranscribesKnownSpeech() async throws {
        guard ProcessInfo.processInfo.environment["LISTEN_RUN_APPLE_SPEECH"] == "1" else {
            throw XCTSkip("Set LISTEN_RUN_APPLE_SPEECH=1 to run the macOS 26 system-model check.")
        }
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Apple Speech requires macOS 26 or later.")
        }

        let samples = try integrationSamples()
        try await assertKnownSpeech(using: .appleSpeechAnalyzer, samples: samples)
    }

    private func integrationSamples() throws -> [Float] {
        guard let audioPath = ProcessInfo.processInfo.environment["LISTEN_INTEGRATION_AUDIO"] else {
            throw XCTSkip("Set LISTEN_INTEGRATION_AUDIO to run the real transcription checks.")
        }

        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(format.channelCount, 1)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw IntegrationError.invalidAudio("Could not allocate the integration audio buffer.")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee else {
            throw IntegrationError.invalidAudio("Integration audio is not Float32 PCM.")
        }

        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private func assertKnownSpeech(
        using model: TranscriptionModel,
        samples: [Float]
    ) async throws {
        let service = TranscriptionService()
        try await service.load(model: model)
        let transcript = try await service.transcribe(audioData: samples).lowercased()

        XCTAssertTrue(transcript.contains("mister quilter"), "Unexpected transcript: \(transcript)")
        XCTAssertTrue(transcript.contains("middle classes"), "Unexpected transcript: \(transcript)")
    }

    private enum IntegrationError: Error {
        case invalidAudio(String)
    }
}
