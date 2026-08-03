import Foundation

/// User-selectable on-device transcription engines.
enum TranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case parakeetUnifiedEnglish = "parakeet-unified-en-0.6b"
    case parakeetV3Multilingual = "parakeet-tdt-0.6b-v3"
    case appleSpeechAnalyzer = "apple-speech-analyzer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeetUnifiedEnglish:
            return "Parakeet Unified"
        case .parakeetV3Multilingual:
            return "Parakeet Multilingual"
        case .appleSpeechAnalyzer:
            return "Apple Speech"
        }
    }

    var description: String {
        switch self {
        case .parakeetUnifiedEnglish:
            return "Best English accuracy and punctuation. Downloads about 614 MB."
        case .parakeetV3Multilingual:
            return "Supports 25 European languages. Use this for non-English dictation."
        case .appleSpeechAnalyzer:
            return "Experimental macOS 26 system model with no app-managed download."
        }
    }

    var loadingDescription: String {
        switch self {
        case .parakeetUnifiedEnglish:
            return "Loading Parakeet Unified..."
        case .parakeetV3Multilingual:
            return "Loading Parakeet Multilingual..."
        case .appleSpeechAnalyzer:
            return "Preparing Apple Speech..."
        }
    }

    /// Preserves the identifier used by pre-1.1 builds if it was ever written by a development build.
    static func fromPersistedValue(_ value: String?) -> TranscriptionModel {
        if value == "parakeet-tdt-0.6b" {
            return .parakeetV3Multilingual
        }
        return value.flatMap(TranscriptionModel.init(rawValue:)) ?? .parakeetUnifiedEnglish
    }

    static func availableModels(macOSMajorVersion: Int) -> [TranscriptionModel] {
        var models: [TranscriptionModel] = [.parakeetUnifiedEnglish, .parakeetV3Multilingual]
        if macOSMajorVersion >= 26 {
            models.append(.appleSpeechAnalyzer)
        }
        return models
    }

    static var availableOnCurrentSystem: [TranscriptionModel] {
        availableModels(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}
