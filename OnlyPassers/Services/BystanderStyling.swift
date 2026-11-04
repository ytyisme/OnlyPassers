import CoreImage
import Foundation

/// 把整张图变成卡通。合成器再用路人蒙版裁切，所以这里不用知道谁是主体。
///
/// 现有实现是 Core Image，照片不出设备。以后可以把一个小的 Core ML 风格模型
/// 做成另一个实现，用 `OnDeviceProcessingService(makeStylist:)` 注入。
/// `effectDescription` 要便宜，不要在里面加载模型。
protocol BystanderStyling: Sendable {
    func stylize(_ image: CIImage, styleID: String) -> CIImage
    func effectDescription(for styleID: String) -> String
}

extension BystanderStyling {
    func effectDescription(for styleID: String) -> String {
        "端侧风格 \(styleID)"
    }
}

/// `cartoon-bystander` / `cartoon-comic`：`CIComicEffect`。
/// `cartoon-poster`：色块加勾线。漫画滤镜不可用时也会退到这条。
struct CoreImageCartoonStylist: BystanderStyling {
    static let posterStyleID = "cartoon-poster"
    static let comicStyleID = "cartoon-comic"

    func effectDescription(for styleID: String) -> String {
        switch styleID {
        case Self.posterStyleID:
            "Core Image 色块描边"
        default:
            "Core Image 卡通"
        }
    }

    func stylize(_ image: CIImage, styleID: String) -> CIImage {
        let styled: CIImage?
        if styleID == Self.posterStyleID {
            styled = posterEdges(image)
        } else if let comic = Self.filter("CIComicEffect", image: image),
                  comic.extent.width > 2,
                  comic.extent.height > 2 {
            styled = comic
        } else {
            styled = posterEdges(image)
        }
        return (styled ?? image).cropped(to: image.extent)
    }

    private func posterEdges(_ input: CIImage) -> CIImage? {
        let saturated = Self.filter("CIColorControls", image: input) { filter in
            filter.setValue(1.45, forKey: "inputSaturation")
            filter.setValue(1.12, forKey: "inputContrast")
            filter.setValue(0.01, forKey: "inputBrightness")
        } ?? input

        let poster = Self.filter("CIColorPosterize", image: saturated) { filter in
            filter.setValue(6, forKey: "inputLevels")
        } ?? saturated

        guard let edges = Self.filter("CIEdges", image: input, configure: { filter in
            filter.setValue(1.2, forKey: "inputIntensity")
        }) else {
            return poster
        }
        let edgeMask = ImageAlign.aligned(edges, to: input.extent)
        let posterAligned = ImageAlign.aligned(poster, to: input.extent)

        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: input.extent)
        let lined = Self.filter("CIBlendWithMask", image: black) { filter in
            filter.setValue(posterAligned, forKey: "inputBackgroundImage")
            filter.setValue(edgeMask, forKey: "inputMaskImage")
        }
        return lined?.cropped(to: input.extent) ?? poster
    }

    static func filter(
        _ name: String,
        image: CIImage,
        configure: ((CIFilter) -> Void)? = nil
    ) -> CIImage? {
        guard let filter = CIFilter(name: name) else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        configure?(filter)
        guard let output = filter.outputImage, !output.extent.isEmpty else { return nil }
        return output
    }
}
