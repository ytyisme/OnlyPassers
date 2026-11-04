import Foundation

/// 把一张照片加工成「路人卡通、主体与风景仍清晰」的结果。
///
/// 生产实现是 `OnDeviceProcessingService`（Vision 蒙版 + Core Image）。
/// `StubProcessingService` 留给 SwiftUI 预览。调用方只依赖这个协议。
/// 约束：只卡通化非主体的人；主体和背景像素保持原图。不要上传照片。
protocol ProcessingService: Sendable {
    func process(_ request: ProcessRequest) async throws -> ProcessResult
}

enum ProcessingError: Error, Equatable, LocalizedError {
    case unreadableImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "无法读取这张照片。"
        case .encodingFailed:
            "无法保存处理结果。"
        }
    }
}
