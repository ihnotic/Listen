import Foundation
import SwiftUI
import Combine
import AVFoundation

/// Simple file logger so we can see logs even when launched via `open`.
func listenLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    NSLog("[Listen] \(msg)")
    let logPath = NSHomeDirectory() + "/Library/Logs/Listen.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

/// Central state object that orchestrates all services.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State
    @Published var isRecording = false
    @Published var isModelLoaded = false
    @Published var isModelLoading = false
    @Published var statusText = "Initializing..."
    @Published var lastTranscription = ""
    @Published var transcriptions: [String] = []
    @Published var errorMessage: String?

    // MARK: - Services
    let audioCaptureService = AudioCaptureService()
    let voiceActivityDetector = VoiceActivityDetector()
    let whisperService = WhisperService()
    let globeKeyMonitor = GlobeKeyMonitor()
    let hotkeyManager = HotkeyManager()
    let textInserter = TextInserter()
    let soundEffects = SoundEffects()
    let permissions = Permissions()

    // MARK: - Config
    var config = AppConfig()

    private var audioTask: Task<Void, Never>?

    init() {
        setupHotkeyCallbacks()
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        listenLog("Bootstrap starting...")

        // Check permissions
        let hasAx = permissions.checkAccessibility()
        listenLog("Accessibility: \(hasAx)")

        if !hasAx {
            permissions.promptAccessibility()
        }

        statusText = "Loading Parakeet model..."
        isModelLoading = true

        do {
            listenLog("Loading Parakeet TDT 0.6B model (auto-downloads on first run)...")
            try await whisperService.loadModel(path: "")  // FluidAudio handles download internally
            isModelLoaded = true
            isModelLoading = false
            statusText = "Ready"
            listenLog("Parakeet model loaded — Ready!")
        } catch {
            isModelLoading = false
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            statusText = "Error"
            listenLog("ERROR loading model: \(error)")
        }

        // Start CGEvent tap for Globe/fn key (needs Input Monitoring permission)
        startGlobeMonitor()

        listenLog("Bootstrap complete.")
    }

    // MARK: - Hotkey Callbacks

    private func setupHotkeyCallbacks() {
        hotkeyManager.onActivate = { [weak self] in
            Task { @MainActor in
                self?.setActive(true)
            }
        }
        hotkeyManager.onDeactivate = { [weak self] in
            Task { @MainActor in
                self?.setActive(false)
            }
        }
    }

    // MARK: - Globe/fn Key (CGEvent tap)

    private func startGlobeMonitor() {
        globeKeyMonitor.onFnDown = { [weak self] in
            self?.hotkeyManager.handleFnDown()
        }
        globeKeyMonitor.onFnUp = { [weak self] in
            self?.hotkeyManager.handleFnUp()
        }
        let success = globeKeyMonitor.start()
        if success {
            listenLog("Globe/fn key monitor started (CGEvent tap).")
        } else {
            listenLog("Globe/fn key monitor FAILED — need Input Monitoring permission.")
        }
    }

    // MARK: - Recording Control

    func setActive(_ active: Bool) {
        guard isModelLoaded else { return }

        if active && !isRecording {
            startRecording()
        } else if !active && isRecording {
            stopRecording()
        }
    }

    func toggleRecording() {
        setActive(!isRecording)
    }

    private func startRecording() {
        listenLog("START recording")
        isRecording = true
        statusText = "Recording..."
        soundEffects.playStartSound()

        // Wire audio levels to the waveform pill
        audioCaptureService.onLevel = { level in
            DispatchQueue.main.async {
                RecordingPillWindow.shared.pushLevel(level)
            }
        }
        RecordingPillWindow.shared.show()

        audioTask = Task {
            do {
                listenLog("Starting audio capture...")
                try audioCaptureService.start()
                listenLog("Audio capture started OK, awaiting segments...")

                for await segment in voiceActivityDetector.processAudio(from: audioCaptureService) {
                    guard !Task.isCancelled else {
                        listenLog("Audio task cancelled")
                        break
                    }
                    listenLog("Got segment: \(segment.count) samples (\(String(format: "%.1f", Float(segment.count) / 16000.0))s)")
                    await transcribeSegment(segment)
                }
                listenLog("Audio stream ended")
            } catch {
                listenLog("Audio capture ERROR: \(error)")
                await MainActor.run {
                    errorMessage = "Audio capture failed: \(error.localizedDescription)"
                    stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        listenLog("STOP recording")
        isRecording = false
        statusText = "Transcribing..."
        soundEffects.playStopSound()
        RecordingPillWindow.shared.hide()

        // IMPORTANT: flush VAD BEFORE stopping audio capture
        // This yields any remaining buffered speech as a final segment
        voiceActivityDetector.flush()

        // Stop audio capture — this finishes the audio stream
        audioCaptureService.stop()

        // Don't cancel audioTask immediately — let it finish processing the flushed segment
        // Set up a delayed cleanup
        let task = audioTask
        audioTask = nil
        Task {
            // Give the transcription task a few seconds to finish processing
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            task?.cancel()
            await MainActor.run {
                if self.statusText == "Transcribing..." {
                    self.statusText = "Ready"
                }
            }
        }
        listenLog("Recording stopped, waiting for transcription...")
    }

    // MARK: - Transcription

    private func transcribeSegment(_ audioData: [Float]) async {
        do {
            listenLog("Transcribing segment: \(audioData.count) samples (\(String(format: "%.1f", Float(audioData.count) / 16000.0))s)")
            let text = try await whisperService.transcribe(audioData: audioData)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            listenLog("Transcription result: '\(trimmed)' (raw: '\(text)')")

            guard !trimmed.isEmpty else {
                listenLog("Transcription was empty, skipping")
                return
            }

            await MainActor.run {
                lastTranscription = trimmed
                transcriptions.append(trimmed)
                statusText = "Ready"
                // Keep bounded
                if transcriptions.count > 200 {
                    transcriptions.removeFirst()
                }
            }

            // Insert text into active app
            listenLog("Inserting text: '\(trimmed)'")
            textInserter.insertText(trimmed)
        } catch {
            listenLog("Transcription ERROR: \(error)")
            await MainActor.run {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                statusText = "Ready"
            }
        }
    }
}
