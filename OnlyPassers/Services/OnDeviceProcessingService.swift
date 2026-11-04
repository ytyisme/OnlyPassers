import CoreImage
import Foundation

enum CartoonOutput: Sendable {
    case unchanged
    /// `workingOriginal` 是参与合成的那张图（可能已限制长边），用来和结果对齐比较。
    case rendered(
        processed: Data,
        workingOriginal: Data,
        source: PasserbyMaskSource,
        affectedCount: Int,
        effectDescription: String
    )
}

enum OnDeviceCartoonPipeline {
    static func render(
        imageData: Data,
        regions: [FaceOrPersonRegion],
        styleID: String,
        stylist: any BystanderStyling
    ) throws -> CartoonOutput {
        let passersby = regions.filter { !$0.isMainSubject }
        guard !passersby.isEmpty else { return .unchanged }

        let cgImage = try ImageCoding.uprightCGImage(from: imageData, maxPixel: PhotoLimits.maxPixelDimension)
        guard let built = PasserbyMaskBuilder.makeMask(cgImage: cgImage, regions: regions) else {
            return .unchanged
        }

        let original = CIImage(cgImage: cgImage)
        let extent = original.extent
        let cartoon = stylist.stylize(original, styleID: styleID)
        let composited = ImageAlign.blend(
            foreground: cartoon,
            background: original,
            mask: built.image,
            extent: extent
        )

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let output = context.createCGImage(composited, from: extent) else {
            throw ProcessingError.encodingFailed
        }
        let processed = try ImageCoding.jpegData(from: output, quality: 0.92)
        let workingOriginal = try ImageCoding.jpegData(from: cgImage, quality: 0.92)
        return .rendered(
            processed: processed,
            workingOriginal: workingOriginal,
            source: built.source,
            affectedCount: built.affectedCount,
            effectDescription: stylist.effectDescription(for: styleID)
        )
    }
}

/// 生产路径：只卡通化非主体的人，主体和风景用原图像素。不上传照片。
struct OnDeviceProcessingService: ProcessingService {
    var regionDetector: any RegionDetecting
    /// 在后台队列调用。默认是 `CoreImageCartoonStylist`。
    /// 注入 Core ML 实现时，不要在创建时碰主线程，也不要联网。
    var makeStylist: @Sendable () -> any BystanderStyling

    init(
        regionDetector: any RegionDetecting = VisionRegionDetector(),
        makeStylist: @escaping @Sendable () -> any BystanderStyling = { CoreImageCartoonStylist() }
    ) {
        self.regionDetector = regionDetector
        self.makeStylist = makeStylist
    }

    func process(_ request: ProcessRequest) async throws -> ProcessResult {
        let regions = try await resolveRegions(for: request)
        let styleID = request.styleID.isEmpty ? ProcessRequest.defaultStyleID : request.styleID
        let data = request.imageData
        let makeStylist = self.makeStylist
        let output = try await Task.detached(priority: .userInitiated) {
            try OnDeviceCartoonPipeline.render(
                imageData: data,
                regions: regions,
                styleID: styleID,
                stylist: makeStylist()
            )
        }.value

        let originalData: Data
        let processed: Data
        switch output {
        case .unchanged:
            originalData = data
            processed = data
        case .rendered(let jpeg, let workingOriginal, _, _, _):
            originalData = workingOriginal
            processed = jpeg
        }

        return ProcessResult(
            originalImageData: originalData,
            processedImageData: processed,
            regions: regions,
            summary: Self.summary(regions: regions, output: output)
        )
    }

    private func resolveRegions(for request: ProcessRequest) async throws -> [FaceOrPersonRegion] {
        let regions: [FaceOrPersonRegion]
        if request.regions.isEmpty {
            regions = try await regionDetector.detectRegions(in: request.imageData)
        } else {
            regions = request.regions
        }
        if regions.isEmpty || regions.contains(where: \.isMainSubject) {
            return regions
        }
        return SubjectSelection.applyDefault(to: regions)
    }

    private static func summary(regions: [FaceOrPersonRegion], output: CartoonOutput) -> String {
        let people = regions.count
        switch output {
        case .unchanged:
            if people == 0 {
                return "没有检测到人，已保留原图。"
            }
            if regions.contains(where: { !$0.isMainSubject }) {
                return "识别到 \(people) 人，但没能生成路人蒙版，已保留原图。"
            }
            return "识别到 \(people) 人，已作为主体保留。没有路人需要卡通化。"
        case .rendered(_, _, let source, let affected, let effect):
            let count = max(affected, 1)
            switch source {
            case .personInstance:
                return "识别到 \(people) 人，已用端侧人物实例蒙版和\(effect)卡通化 \(count) 位路人。主体与风景保持原图。"
            case .personSegmentation:
                return "识别到 \(people) 人，已用端侧人物分割和\(effect)卡通化 \(count) 位路人。主体与风景保持原图。"
            case .boundingBox:
                return "识别到 \(people) 人。这台设备没有给出人物蒙版，已按路人框用\(effect)卡通化 \(count) 位路人。主体框内和框外风景保持原图。"
            }
        }
    }
}
