import CoreGraphics
import Foundation

/// 一张图里的人脸或人物区域。
///
/// 归一化坐标的原点在**左上角**，与 UIKit 一致，范围约 `0...1`。
/// Vision 的 `boundingBox` 原点在左下角，`VisionRegionDetector` 会先换算再填这个结构。
/// 预览里点选主体后，`isMainSubject` 会写回 `ProcessRequest.regions`。
struct FaceOrPersonRegion: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Equatable, Codable, Sendable {
        /// 人脸框，例如 `VNDetectFaceRectanglesRequest`。
        case face
        /// 整个人，例如 `VNGeneratePersonSegmentationRequest` 的外接框。
        case person
    }

    var id: UUID
    var kind: Kind
    var boundingBox: CGRect
    /// 为真时保持清晰、写实，不参与卡通化。
    var isMainSubject: Bool
    /// 检测置信度。占位区域用 `0`，不代表模型分数。
    var confidence: Float

    var roleTitle: String {
        isMainSubject ? "主体 · 保持清晰" : "路人 · 将卡通化"
    }

    /// 处理完成后的角色说明。
    var resultRoleTitle: String {
        isMainSubject ? "主体清晰" : "路人卡通"
    }

    var kindTitle: String {
        switch kind {
        case .face: "人脸"
        case .person: "人物"
        }
    }
}
