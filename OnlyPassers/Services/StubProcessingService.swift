import UIKit

/// 预览用占位流水线：不读照片内容，只在图上画出主体 / 路人示意框。
/// 真机路径是 `OnDeviceProcessingService`，不要在正式界面里用这个类型。
struct StubProcessingService: ProcessingService {
    var regionDetector: any RegionDetecting = StubRegionDetector()

    func process(_ request: ProcessRequest) async throws -> ProcessResult {
        let regions = try await resolveRegions(for: request)
        let processed = try await Self.mark(imageData: request.imageData, regions: regions)
        return ProcessResult(
            originalImageData: request.imageData,
            processedImageData: processed,
            regions: regions,
            summary: "占位处理：已标出主体与路人。真实的卡通化尚未接入。"
        )
    }

    private func resolveRegions(for request: ProcessRequest) async throws -> [FaceOrPersonRegion] {
        if request.regions.isEmpty {
            return try await regionDetector.detectRegions(in: request.imageData)
        }
        return request.regions
    }

    @MainActor
    private static func mark(imageData: Data, regions: [FaceOrPersonRegion]) throws -> Data {
        guard let image = UIImage(data: imageData),
              image.size.width > 1,
              image.size.height > 1 else {
            throw ProcessingError.unreadableImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let output = renderer.image { _ in
            // 渲染闭包不一定继承 MainActor，这里同步切回主线程上下文再画 UIKit。
            MainActor.assumeIsolated {
                image.draw(in: CGRect(origin: .zero, size: image.size))
                let canvas = image.size
                let lineWidth = max(2, min(canvas.width, canvas.height) * 0.006)
                for region in regions {
                    Self.draw(region, on: canvas, lineWidth: lineWidth)
                }
                Self.drawBanner(on: canvas)
            }
        }

        guard let data = output.jpegData(compressionQuality: 0.92) else {
            throw ProcessingError.encodingFailed
        }
        return data
    }

    @MainActor
    private static func draw(_ region: FaceOrPersonRegion, on canvas: CGSize, lineWidth: CGFloat) {
        let rect = CGRect(
            x: region.boundingBox.origin.x * canvas.width,
            y: region.boundingBox.origin.y * canvas.height,
            width: region.boundingBox.width * canvas.width,
            height: region.boundingBox.height * canvas.height
        ).intersection(CGRect(origin: .zero, size: canvas))
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return }

        let color = region.isMainSubject
            ? UIColor(red: 0.12, green: 0.55, blue: 0.36, alpha: 1)
            : UIColor(red: 0.90, green: 0.38, blue: 0.18, alpha: 1)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: lineWidth * 2)

        color.withAlphaComponent(0.14).setFill()
        path.fill()
        UIColor.white.withAlphaComponent(0.92).setStroke()
        path.lineWidth = lineWidth + max(1, lineWidth * 0.45)
        path.stroke()
        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()

        drawLabel(
            region.roleTitle,
            near: rect,
            color: color,
            canvas: canvas,
            fontSize: max(14, canvas.width * 0.028)
        )
    }

    @MainActor
    private static func drawLabel(
        _ text: String,
        near rect: CGRect,
        color: UIColor,
        canvas: CGSize,
        fontSize: CGFloat
    ) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding = fontSize * 0.38
        var label = CGRect(
            x: rect.minX,
            y: rect.minY - textSize.height - padding * 2 - fontSize * 0.25,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        if label.minY < fontSize * 0.2 {
            label.origin.y = rect.minY + fontSize * 0.35
        }
        if label.maxX > canvas.width - 4 {
            label.origin.x = max(4, canvas.width - label.width - 4)
        }

        color.setFill()
        UIBezierPath(roundedRect: label, cornerRadius: label.height / 2).fill()
        let origin = CGPoint(x: label.minX + padding, y: label.minY + padding)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    @MainActor
    private static func drawBanner(on canvas: CGSize) {
        let height = max(36, canvas.height * 0.055)
        let bar = CGRect(x: 0, y: canvas.height - height, width: canvas.width, height: height)
        UIColor.black.withAlphaComponent(0.58).setFill()
        UIBezierPath(rect: bar).fill()

        let fontSize = max(13, min(height * 0.42, canvas.width * 0.03))
        let text = "占位 · 尚未卡通化"
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(
            x: (canvas.width - textSize.width) / 2,
            y: bar.minY + (height - textSize.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
