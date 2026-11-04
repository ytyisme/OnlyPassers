import Foundation

/// 找出图中的人脸 / 人物。
///
/// 接入点：`VNDetectFaceRectanglesRequest`、`VNGeneratePersonSegmentationRequest`。
/// 返回值使用左上角归一化坐标，不要直接把 Vision 的左下角 `boundingBox` 交出去。
protocol RegionDetecting: Sendable {
    func detectRegions(in imageData: Data) async throws -> [FaceOrPersonRegion]
}
