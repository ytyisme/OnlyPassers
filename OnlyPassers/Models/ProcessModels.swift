import Foundation

/// 一次处理请求。`regions` 为空时，由 `RegionDetecting` 产生区域。
/// 主体选择做好之后，界面可以把用户确认过的区域填进来。
struct ProcessRequest: Equatable, Codable, Sendable {
    /// 预留给卡通风格。占位实现不解释这个值。
    static let placeholderStyleID = "cartoon-bystander"

    var imageData: Data
    var regions: [FaceOrPersonRegion]
    var styleID: String
}

/// 处理结果。真正的实现里，`processedImageData` 应是合成图：
/// 风景和主体用原图像素，只有非主体的人被卡通化。
struct ProcessResult: Equatable, Codable, Sendable {
    var originalImageData: Data
    var processedImageData: Data
    var regions: [FaceOrPersonRegion]
    var summary: String
}
