# Listen

Native macOS speech-to-text. Runs entirely on your machine — no cloud, no API keys, no data leaves your device.

Powered by [NVIDIA Parakeet Unified EN 0.6B](https://huggingface.co/nvidia/parakeet-unified-en-0.6b) running on Apple Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio). Parakeet TDT v3 remains available for multilingual dictation, with Apple Speech as an experimental macOS 26 option.

## Features

- **Native macOS app** — lightweight Swift menu bar app, no Electron, no Python
- **Push-to-talk** — hold the Globe (fn) key to record, release to transcribe and paste
- **Fast and accurate** — Parakeet Unified 0.6B runs on Apple Neural Engine via CoreML
- **Selectable models** — English-first Unified, multilingual Parakeet v3, or experimental Apple Speech
- **Types into any app** — transcribed text is pasted directly into the active application
- **Dynamic waveform** — floating pill shows a live audio waveform while recording
- **Fully local** — everything runs on-device, nothing is sent to the cloud

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1 or later recommended for Neural Engine)

## Install

### Build from source

```bash
git clone https://github.com/BradleyFarquharson/Listen.git
cd Listen
chmod +x build.sh
./build.sh
```

This builds `Listen.app` in the `dist/` directory. Copy it to `/Applications/`:

```bash
cp -r dist/Listen.app /Applications/
```

The build uses the first available macOS code-signing identity. If none is
installed, it falls back to an ad-hoc signature so the local app can launch.
With ad-hoc signing, macOS privacy permissions may need to be granted again
after future rebuilds.

### First launch

On first launch, Listen downloads the Parakeet Unified INT8 model (~614MB). This only happens once. The multilingual model is downloaded separately if selected; Apple Speech uses a macOS-managed system asset.

## Usage

1. Launch Listen — a microphone icon appears in the menu bar
2. Grant **Input Monitoring** and **Microphone** permissions when prompted
3. Open any text field (TextEdit, browser, Slack, etc.)
4. **Hold the Globe (fn) key** — a floating waveform pill appears at the bottom of the screen
5. Speak naturally
6. **Release the Globe key** — your speech is transcribed and typed into the active app

## Permissions

Listen needs two macOS permissions:

| Permission | Why | Where to grant |
|---|---|---|
| **Input Monitoring** | Globe (fn) key detection | System Settings > Privacy & Security > Input Monitoring |
| **Microphone** | Audio capture | System Settings > Privacy & Security > Microphone |

Both are prompted automatically on first use.

## Architecture

```
Listen/
  App/
    ListenApp.swift              — @main SwiftUI MenuBarExtra entry point
    AppState.swift               — Central orchestrator
  Audio/
    AudioCaptureService.swift    — AVAudioEngine mic capture (16kHz mono)
    VoiceActivityDetector.swift  — RMS energy-based speech segmentation
  Transcription/
    WhisperService.swift         — Selectable Unified, multilingual, and Apple Speech backends
    TranscriptionModel.swift     — Persisted model selection and availability
  Input/
    GlobeKeyMonitor.swift        — CGEvent tap for Globe (fn) key
    HotkeyManager.swift          — Push-to-talk / toggle-mute modes
    TextInserter.swift           — Clipboard + CGEvent Cmd+V paste
  UI/
    MenuBarView.swift            — Menu bar dropdown
    RecordingPillView.swift      — Dynamic waveform visualization
    RecordingPillWindow.swift    — Floating NSPanel overlay
    SettingsView.swift           — Settings form
  Config/
    AppConfig.swift              — @AppStorage-backed settings
    Permissions.swift            — Permission checks
  Utilities/
    SoundEffects.swift           — Start/stop audio cues
```

## How it works

1. Globe (fn) key press detected via CGEvent tap (Input Monitoring permission)
2. AVAudioEngine captures microphone audio, resampled to 16kHz mono
3. Voice activity detection buffers the utterance until the hotkey is released
4. The selected on-device model transcribes the complete utterance
5. Transcribed text is inserted into the active app via clipboard + simulated Cmd+V

## Tech stack

| Component | Technology |
|---|---|
| Language | Swift |
| UI | SwiftUI MenuBarExtra + NSPanel |
| Default STT model | NVIDIA Parakeet Unified EN 0.6B INT8 |
| Optional STT models | Parakeet TDT 0.6B v3; Apple Speech on macOS 26 |
| Inference | CoreML / Apple Neural Engine via FluidAudio |
| Audio | AVAudioEngine |
| Hotkey | CGEvent tap (Input Monitoring) |
| Text insertion | CGEvent keyboard simulation |
| Config | @AppStorage (UserDefaults) |

## License

[MIT](LICENSE)

The NVIDIA Parakeet TDT model is licensed under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
