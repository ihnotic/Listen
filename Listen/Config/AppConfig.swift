import Foundation

/// App configuration backed by @AppStorage / UserDefaults.
final class AppConfig: ObservableObject {
    // MARK: - Model
    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "modelName") }
    }

    // MARK: - Mode
    @Published var mode: RecordingMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }

    // MARK: - Audio
    @Published var sampleRate: Int = 16000
    @Published var channels: Int = 1

    // MARK: - VAD
    @Published var energyThreshold: Float {
        didSet { UserDefaults.standard.set(energyThreshold, forKey: "energyThreshold") }
    }
    @Published var minSpeechMs: Int {
        didSet { UserDefaults.standard.set(minSpeechMs, forKey: "minSpeechMs") }
    }
    @Published var minSilenceMs: Int {
        didSet { UserDefaults.standard.set(minSilenceMs, forKey: "minSilenceMs") }
    }

    enum RecordingMode: String, CaseIterable {
        case pushToTalk = "push-to-talk"
        case toggleMute = "toggle-mute"

        var displayName: String {
            switch self {
            case .pushToTalk: return "Push to Talk"
            case .toggleMute: return "Toggle Mute"
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.modelName = defaults.string(forKey: "modelName") ?? "ggml-base.en"
        self.mode = RecordingMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .pushToTalk
        self.energyThreshold = defaults.object(forKey: "energyThreshold") as? Float ?? 0.01
        self.minSpeechMs = defaults.object(forKey: "minSpeechMs") as? Int ?? 250
        self.minSilenceMs = defaults.object(forKey: "minSilenceMs") as? Int ?? 700
    }
}
