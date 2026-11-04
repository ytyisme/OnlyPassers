import Foundation

/// 一次处理请求。`regions` 为空时，由 `RegionDetecting` 产生区域并带上默认主体。
/// 预览里点选之后，把改过 `isMainSubject` 的区域填进来，处理时不再改主体。
struct ProcessRequest: Equatable, Codable, Sendable {
    /// 默认端侧风格。`CoreImageCartoonStylist` 会画成漫画风。
    /// `cartoon-poster` 是色块描边。未知 id 仍走端侧卡通，方便以后换 Core ML。
    static let defaultStyleID = "cartoon-bystander"
    static let posterStyleID = "cartoon-poster"
    /// 与 `defaultStyleID` 相同，保留旧名字。
    static let placeholderStyleID = defaultStyleID

    var imageData: Data
    var regions: [FaceOrPersonRegion]
    var styleID: String
}

/// 处理结果。`processedImageData` 是合成图：风景和主体用原图像素，只有非主体的人被卡通化。
/// 没有路人时，两份图数据相同。
struct ProcessResult: Equatable, Codable, Sendable {
    var originalImageData: Data
    var processedImageData: Data
    var regions: [FaceOrPersonRegion]
    var summary: String
}
