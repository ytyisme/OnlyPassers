import Foundation
import Observation
import UIKit

/// 选图 → 预览里点选主体 → 处理 → 对比。
/// 检测和卡通化都在设备上完成，界面只拿到区域和处理结果。
@MainActor
@Observable
final class AppModel {
    enum Step: Equatable {
        case capture
        case preview
        case result
    }

    private let processing: any ProcessingService
    private let detecting: any RegionDetecting
    private var preparedImageData: Data?

    var step: Step = .capture
    var originalImage: UIImage?
    var result: ProcessResult?
    var isProcessing = false
    var isDetecting = false
    var didDetect = false
    var errorMessage: String?
    var regions: [FaceOrPersonRegion] = []
    var photoToken = UUID()

    init(
        processing: any ProcessingService = OnDeviceProcessingService(),
        detecting: any RegionDetecting = VisionRegionDetector()
    ) {
        self.processing = processing
        self.detecting = detecting
    }

    var processedImage: UIImage? {
        guard let data = result?.processedImageData else { return nil }
        return UIImage(data: data)
    }

    var passerbyCount: Int {
        regions.filter { !$0.isMainSubject }.count
    }

    func setPhoto(_ image: UIImage) {
        let upright = image.uprightPixels()
        originalImage = upright
        preparedImageData = upright.jpegData(compressionQuality: 0.92)
        result = nil
        regions = []
        didDetect = false
        isDetecting = false
        isProcessing = false
        photoToken = UUID()
        errorMessage = preparedImageData == nil ? "无法读取这张照片。" : nil
        step = .preview
    }

    func reset() {
        originalImage = nil
        preparedImageData = nil
        result = nil
        regions = []
        didDetect = false
        isDetecting = false
        isProcessing = false
        errorMessage = nil
        photoToken = UUID()
        step = .capture
    }

    func detectSubjects() async {
        let token = photoToken
        guard let data = preparedImageData else {
            if photoToken == token {
                didDetect = true
                isDetecting = false
            }
            return
        }

        isDetecting = true
        defer {
            if photoToken == token {
                isDetecting = false
                didDetect = true
            }
        }

        do {
            let found = try await detecting.detectRegions(in: data)
            guard photoToken == token, !Task.isCancelled else { return }
            regions = found
        } catch is CancellationError {
            return
        } catch {
            guard photoToken == token, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func selectSubject(id: UUID) {
        guard regions.contains(where: { $0.id == id }) else { return }
        regions = regions.map { region in
            var updated = region
            updated.isMainSubject = region.id == id
            return updated
        }
    }

    func process() async {
        guard !isProcessing else { return }
        guard let data = preparedImageData else {
            errorMessage = "无法读取这张照片。"
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let request = ProcessRequest(
            imageData: data,
            regions: regions,
            styleID: ProcessRequest.defaultStyleID
        )

        do {
            result = try await processing.process(request)
            step = .result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
