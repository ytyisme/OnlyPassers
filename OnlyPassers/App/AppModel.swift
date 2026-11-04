import Observation
import UIKit

/// 选图 → 预览 → 处理 → 对比。处理本身交给 `ProcessingService`，界面不关心是占位还是将来的模型。
@MainActor
@Observable
final class AppModel {
    enum Step: Equatable {
        case capture
        case preview
        case result
    }

    private let processing: any ProcessingService

    var step: Step = .capture
    var originalImage: UIImage?
    var result: ProcessResult?
    var isProcessing = false
    var errorMessage: String?

    init(processing: any ProcessingService = StubProcessingService()) {
        self.processing = processing
    }

    var processedImage: UIImage? {
        guard let data = result?.processedImageData else { return nil }
        return UIImage(data: data)
    }

    func setPhoto(_ image: UIImage) {
        originalImage = image
        result = nil
        errorMessage = nil
        step = .preview
    }

    func reset() {
        originalImage = nil
        result = nil
        isProcessing = false
        errorMessage = nil
        step = .capture
    }

    func process() async {
        guard !isProcessing else { return }
        guard let image = originalImage, let data = image.jpegData(compressionQuality: 0.95) else {
            errorMessage = "无法读取这张照片。"
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let request = ProcessRequest(
            imageData: data,
            regions: [],
            styleID: ProcessRequest.placeholderStyleID
        )

        do {
            result = try await processing.process(request)
            step = .result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
