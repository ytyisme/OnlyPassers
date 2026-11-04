import CoreGraphics
import Foundation

/// 固定的三块示意区域：中间是主体，左右是路人。
/// 不读图像内容，也不能当成检测结果。
struct StubRegionDetector: RegionDetecting {
    func detectRegions(in _: Data) async throws -> [FaceOrPersonRegion] {
        Self.placeholders
    }

    static let placeholders: [FaceOrPersonRegion] = [
        FaceOrPersonRegion(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!,
            kind: .person,
            boundingBox: CGRect(x: 0.28, y: 0.16, width: 0.44, height: 0.72),
            isMainSubject: true,
            confidence: 0
        ),
        FaceOrPersonRegion(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000002")!,
            kind: .person,
            boundingBox: CGRect(x: 0.04, y: 0.30, width: 0.20, height: 0.52),
            isMainSubject: false,
            confidence: 0
        ),
        FaceOrPersonRegion(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000003")!,
            kind: .person,
            boundingBox: CGRect(x: 0.76, y: 0.34, width: 0.18, height: 0.48),
            isMainSubject: false,
            confidence: 0
        ),
    ]
}
