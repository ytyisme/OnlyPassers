import SwiftUI

enum RolePalette {
    static let subject = Color(red: 0.12, green: 0.55, blue: 0.36)
    static let passerby = Color(red: 0.90, green: 0.38, blue: 0.18)
}

/// 在按比例适配的照片上画出可点的人物框。坐标是左上角归一化。
struct SubjectOverlayView: View {
    var image: UIImage
    var regions: [FaceOrPersonRegion]
    var isDetecting: Bool
    var onSelect: (UUID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fitted = AspectFit.rect(imageSize: image.size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .accessibilityLabel("原图")

                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    let rect = CGRect(
                        x: region.boundingBox.minX * fitted.width,
                        y: region.boundingBox.minY * fitted.height,
                        width: region.boundingBox.width * fitted.width,
                        height: region.boundingBox.height * fitted.height
                    )
                    if rect.width >= 8, rect.height >= 8 {
                        SubjectBox(index: index + 1, region: region) {
                            onSelect(region.id)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if isDetecting {
                    ProgressView("正在识别人物…")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct SubjectBox: View {
    var index: Int
    var region: FaceOrPersonRegion
    var action: () -> Void

    private var color: Color {
        region.isMainSubject ? RolePalette.subject : RolePalette.passerby
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(region.isMainSubject ? 0.2 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.92), lineWidth: region.isMainSubject ? 5 : 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(color, lineWidth: region.isMainSubject ? 3 : 2)
                }
                .overlay(alignment: .topLeading) {
                    Text("\(index) \(region.isMainSubject ? "主体" : "路人")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color, in: Capsule())
                        .padding(4)
                }
        }
        .buttonStyle(.plain)
    }
}

enum AspectFit {
    static func rect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 1,
              imageSize.height > 1,
              container.width > 1,
              container.height > 1 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}
