import Foundation

/// Manages whisper model files — finding bundled models or downloading them.
final class ModelManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false

    private let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Listen/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Known model download URLs (Hugging Face).
    private static let modelURLs: [String: String] = [
        "ggml-base.en": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
        "ggml-small.en": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
        "ggml-tiny.en": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
        "ggml-medium.en": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin",
    ]

    /// Ensure a model is available — returns the file path.
    /// Checks: 1) App bundle Resources, 2) Application Support, 3) Downloads from HF.
    func ensureModel(named name: String) async throws -> String {
        // 1. Check app bundle
        let bundledName = "\(name).bin"
        if let bundledPath = Bundle.main.path(forResource: name, ofType: "bin") {
            return bundledPath
        }

        // 2. Check Application Support
        let localPath = modelsDirectory.appendingPathComponent(bundledName)
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath.path
        }

        // 3. Download
        guard let urlString = Self.modelURLs[name],
              let url = URL(string: urlString) else {
            throw ModelError.unknownModel(name)
        }

        return try await downloadModel(from: url, to: localPath)
    }

    private func downloadModel(from url: URL, to destination: URL) async throws -> String {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: DownloadDelegate { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
            }
        })

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)

        await MainActor.run {
            isDownloading = false
            downloadProgress = 1.0
        }

        return destination.path
    }

    enum ModelError: Error, LocalizedError {
        case unknownModel(String)
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .unknownModel(let name): return "Unknown model: \(name)"
            case .downloadFailed: return "Failed to download model"
            }
        }
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled in the async download method
    }
}
