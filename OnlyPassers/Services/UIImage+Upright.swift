import UIKit

extension UIImage {
    /// 把像素画成 `.up`，长边超过处理上限时一并缩小。
    /// 预览、检测和合成因此共用同一套左上角坐标。
    @MainActor
    func uprightPixels(maxPixel: CGFloat = PhotoLimits.maxPixelDimension) -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        guard pixelWidth > 1, pixelHeight > 1 else { return self }

        let longest = max(pixelWidth, pixelHeight)
        let ratio = longest > maxPixel ? maxPixel / longest : 1
        if imageOrientation == .up, ratio == 1 {
            return self
        }

        let target = CGSize(
            width: max(1, (pixelWidth * ratio).rounded()),
            height: max(1, (pixelHeight * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            MainActor.assumeIsolated {
                self.draw(in: CGRect(origin: .zero, size: target))
            }
        }
    }
}
