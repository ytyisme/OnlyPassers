import CoreGraphics

/// 归一化框的几何。区域坐标原点在左上角，和 `FaceOrPersonRegion` 一致。
enum SubjectGeometry {
    /// Vision 的 `boundingBox` 原点在左下角。这里换成左上角归一化坐标。
    static func topLeft(fromVisionBottomLeft vision: CGRect) -> CGRect {
        CGRect(
            x: vision.origin.x,
            y: 1 - vision.origin.y - vision.height,
            width: vision.width,
            height: vision.height
        ).clampedToUnitSquare()
    }

    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - intersectionArea
        guard union > 0 else { return 0 }
        return intersectionArea / union
    }

    /// `a` 有多少比例落在 `b` 里。用来判断人脸是不是在某个人物框内。
    static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let area = a.width * a.height
        guard area > 0 else { return 0 }
        return (intersection.width * intersection.height) / area
    }

    static func contains(_ box: CGRect, point: CGPoint, slop: CGFloat) -> Bool {
        box.insetBy(dx: -slop, dy: -slop).contains(point)
    }

    /// 框与实例蒙版是否是同一个人。包含关系给一个最低分，避免人脸框和全身框 IoU 太低。
    static func matchScore(_ region: CGRect, _ instance: CGRect) -> CGFloat {
        let overlap = intersectionOverUnion(region, instance)
        let regionCenter = CGPoint(x: region.midX, y: region.midY)
        let instanceCenter = CGPoint(x: instance.midX, y: instance.midY)
        if contains(instance, point: regionCenter, slop: 0.02)
            || contains(region, point: instanceCenter, slop: 0.02) {
            return max(overlap, 0.55)
        }
        return overlap
    }

    /// 越大、越靠近画面中心，分数越高。
    /// `0.62 * sqrt(面积) + 0.38 * 居中程度`。居中程度在正中是 1，在角上是 0。
    static func prominence(of box: CGRect) -> CGFloat {
        let clamped = box.clampedToUnitSquare()
        let area = max(0, clamped.width) * max(0, clamped.height)
        guard area > 0 else { return 0 }
        let dx = clamped.midX - 0.5
        let dy = clamped.midY - 0.5
        let distance = (dx * dx + dy * dy).squareRoot()
        let maxDistance = (0.5 * 0.5 + 0.5 * 0.5).squareRoot()
        let centrality = 1 - min(1, distance / maxDistance)
        return 0.62 * area.squareRoot() + 0.38 * centrality
    }

    /// 只有人脸时，向下扩成一个大致的身体范围，供框形蒙版使用。
    static func estimatedPersonBox(fromFace face: CGRect) -> CGRect {
        let width = face.width * 2.4
        let height = face.height * 6
        let rect = CGRect(
            x: face.midX - width / 2,
            y: face.minY - face.height * 0.35,
            width: width,
            height: height
        )
        return rect.clampedToUnitSquare()
    }

    static func effectBox(for region: FaceOrPersonRegion) -> CGRect {
        switch region.kind {
        case .person:
            region.boundingBox.insetBy(dx: -0.012, dy: -0.01).clampedToUnitSquare()
        case .face:
            estimatedPersonBox(fromFace: region.boundingBox)
        }
    }

    /// 比效果框稍大，用来在分割不精确时保住主体。
    static func protectionBox(for region: FaceOrPersonRegion) -> CGRect {
        switch region.kind {
        case .person:
            region.boundingBox.insetBy(dx: -0.03, dy: -0.025).clampedToUnitSquare()
        case .face:
            estimatedPersonBox(fromFace: region.boundingBox)
        }
    }
}

extension CGRect {
    func clampedToUnitSquare() -> CGRect {
        let x0 = min(max(min(origin.x, origin.x + width), 0), 1)
        let y0 = min(max(min(origin.y, origin.y + height), 0), 1)
        let x1 = min(max(max(origin.x, origin.x + width), 0), 1)
        let y1 = min(max(max(origin.y, origin.y + height), 0), 1)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}
