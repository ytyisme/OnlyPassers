import Foundation

/// 找出图中的人脸 / 人物。
///
/// 生产实现是 `VisionRegionDetector`。`StubRegionDetector` 留给预览。
/// 返回值使用左上角归一化坐标。Vision 的左下角 `boundingBox` 要在检测器里换算。
protocol RegionDetecting: Sendable {
    func detectRegions(in imageData: Data) async throws -> [FaceOrPersonRegion]
}
