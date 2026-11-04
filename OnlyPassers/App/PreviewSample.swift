#if DEBUG
import UIKit

/// SwiftUI 预览用的简单风景，不是运行时资源。
enum PreviewSample {
    @MainActor
    static func scene() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.55, green: 0.74, blue: 0.86, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor(red: 0.95, green: 0.86, blue: 0.55, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 640, y: 80, width: 140, height: 140))

            UIColor(red: 0.62, green: 0.74, blue: 0.48, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 780, width: size.width, height: 420))

            func person(x: CGFloat, y: CGFloat, scale: CGFloat, color: UIColor) {
                color.setFill()
                let head = CGRect(x: x, y: y, width: 70 * scale, height: 70 * scale)
                context.cgContext.fillEllipse(in: head)
                let body = CGRect(
                    x: x - 20 * scale,
                    y: y + 78 * scale,
                    width: 110 * scale,
                    height: 220 * scale
                )
                let path = UIBezierPath(roundedRect: body, cornerRadius: 28 * scale)
                path.fill()
            }

            person(x: 120, y: 430, scale: 0.85, color: UIColor(red: 0.86, green: 0.45, blue: 0.28, alpha: 1))
            person(x: 390, y: 340, scale: 1.35, color: UIColor(red: 0.16, green: 0.24, blue: 0.32, alpha: 1))
            person(x: 690, y: 470, scale: 0.75, color: UIColor(red: 0.93, green: 0.62, blue: 0.28, alpha: 1))
        }
    }
}
#endif
