import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoLimits {
    /// Vision 和合成共用的长边上限。再大时 Core Image 漫画效果容易占满内存。
    static let maxPixelDimension: CGFloat = 2048
}

enum ImageCoding {
    /// 按 EXIF 方向转正，并把长边限制在 `maxPixel`。返回的像素原点就是画面左上角。
    static func uprightCGImage(from data: Data, maxPixel: CGFloat) throws -> CGImage {
        guard let image = CIImage(data: data) else {
            throw ProcessingError.unreadableImage
        }
        var extent = image.extent
        guard extent.width > 1, extent.height > 1, extent.width.isFinite, extent.height.isFinite else {
            throw ProcessingError.unreadableImage
        }

        var working = image
        let longest = max(extent.width, extent.height)
        if longest > maxPixel {
            let scale = maxPixel / longest
            working = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            extent = working.extent
        }

        let integral = extent.integral
        guard integral.width > 1, integral.height > 1 else {
            throw ProcessingError.unreadableImage
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(working, from: integral) else {
            throw ProcessingError.unreadableImage
        }
        return rendered
    }

    static func jpegData(from image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ProcessingError.encodingFailed
        }
        let options = [
            kCGImageDestinationLossyCompressionQuality: NSNumber(value: Double(quality)),
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw ProcessingError.encodingFailed
        }
        return data as Data
    }
}
