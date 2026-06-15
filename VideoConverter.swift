import AVFoundation

final class VideoConverter: ObservableObject {
    @Published var isConverting = false
    @Published var conversionProgress: Float = 0
    @Published var conversionError: String?

    private var exportTask: Task<Void, Never>?

    func convertVideoToAudio(from url: URL) async throws -> Data {
        isConverting = true
        conversionProgress = 0
        conversionError = nil

        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            isConverting = false
            throw VideoConverterError.exportSessionCreationFailed
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.conversionProgress = exportSession.progress
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        isConverting = false

        switch exportSession.status {
        case .completed:
            let data = try Data(contentsOf: outputURL)
            try? FileManager.default.removeItem(at: outputURL)
            return data
        case .failed:
            throw exportSession.error ?? VideoConverterError.exportFailed
        case .cancelled:
            throw VideoConverterError.exportCancelled
        default:
            throw VideoConverterError.exportFailed
        }
    }

    func cancelConversion() {
        exportTask?.cancel()
        isConverting = false
    }
}

enum VideoConverterError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "无法创建导出会话"
        case .exportFailed:
            return "视频转换失败"
        case .exportCancelled:
            return "转换已取消"
        case .noAudioTrack:
            return "视频中未找到音轨"
        }
    }
}