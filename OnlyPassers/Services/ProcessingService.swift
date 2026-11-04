import Foundation

/// 把一张照片加工成「路人卡通、主体与风景仍清晰」的结果。
///
/// 现在只有 `StubProcessingService`。以后把 Vision 分割和风格迁移 / 生成式卡通
/// 接在具体实现里，调用方（`AppModel`）不用改。
/// 约束：只卡通化非主体的人；主体和背景像素保持原图。
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
