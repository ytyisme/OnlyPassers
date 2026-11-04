import CoreImage
import CoreVideo
import Foundation
import Vision

enum PasserbyMaskSource: Sendable {
    /// 每个人一张实例蒙版，只把非主体实例放进卡通。
    case personInstance
    /// 全体人物分割减去主体框。实例蒙版不可用时的退路。
    case personSegmentation
    /// 按路人框铺一块柔和蒙版。分割都失败时的退路，主体框会被挖空。
    case boundingBox
}

struct PasserbyMask {
    var image: CIImage
    var source: PasserbyMaskSource
    var affectedCount: Int
}

/// 白色表示要卡通化的路人，黑色表示保持原图（主体和风景）。
enum PasserbyMaskBuilder {
    static func makeMask(cgImage: CGImage, regions: [FaceOrPersonRegion]) -> PasserbyMask? {
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )
        guard extent.width > 1, extent.height > 1 else { return nil }
        if let instance = instanceMask(cgImage: cgImage, regions: regions, extent: extent) {
            return instance
        }
        if let segmentation = segmentationMask(cgImage: cgImage, regions: regions, extent: extent) {
            return segmentation
        }
        return geometricMask(regions: regions, extent: extent)
    }

    private static func instanceMask(
        cgImage: CGImage,
        regions: [FaceOrPersonRegion],
        extent: CGRect
    ) -> PasserbyMask? {
        let request = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            OnlyPassersLog.vision.error(
                "Instance mask for compose failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        guard let observation: VNInstanceMaskObservation = VisionResults.observations(request).first,
              let map = InstanceMaskMap(buffer: observation.instanceMask),
              !map.boxes.isEmpty else {
            return nil
        }

        let plan = MaskAssignment.plan(
            regions: regions,
            instanceBoxes: map.boxes,
            labelAt: { map.label(atTopLeft: $0) }
        )
        guard !plan.passerbyLabels.isEmpty else { return nil }

        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateScaledMaskForImage(
                forInstances: IndexSet(plan.passerbyLabels),
                from: handler
            )
        } catch {
            OnlyPassersLog.vision.error(
                "Scaled instance mask failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        var mask = ImageAlign.aligned(CIImage(cvPixelBuffer: buffer), to: extent)
        if !plan.unmatchedPasserbyRegions.isEmpty {
            let blobs = unionMask(
                plan.unmatchedPasserbyRegions.map { SubjectGeometry.effectBox(for: $0) },
                extent: extent
            )
            mask = ImageAlign.lighten(mask, blobs, extent: extent)
        }

        let subjects = regions.filter(\.isMainSubject)
        let needsPunch = !plan.unmatchedPasserbyRegions.isEmpty || !plan.matchedAllSubjects
        if needsPunch, !subjects.isEmpty {
            mask = punchOut(
                mask,
                boxes: subjects.map { SubjectGeometry.protectionBox(for: $0) },
                extent: extent
            )
        }

        let feathered = feather(
            erode(mask, radius: max(1.2, extent.width * 0.0012), extent: extent),
            radius: max(0.8, extent.width * 0.0008),
            extent: extent
        )
        let affected = plan.passerbyLabels.count + plan.unmatchedPasserbyRegions.count
        guard affected > 0 else { return nil }
        return PasserbyMask(image: feathered, source: .personInstance, affectedCount: affected)
    }

    private static func segmentationMask(
        cgImage: CGImage,
        regions: [FaceOrPersonRegion],
        extent: CGRect
    ) -> PasserbyMask? {
        let passersby = regions.filter { !$0.isMainSubject }
        guard !passersby.isEmpty else { return nil }

        let matte = personMatte(cgImage: cgImage, extent: extent)
        guard let matte else { return nil }

        let subjects = regions.filter(\.isMainSubject)
        let punched = subjects.isEmpty
            ? matte
            : punchOut(matte, boxes: subjects.map { SubjectGeometry.protectionBox(for: $0) }, extent: extent)
        let feathered = feather(punched, radius: max(1.5, extent.width * 0.002), extent: extent)
        return PasserbyMask(image: feathered, source: .personSegmentation, affectedCount: passersby.count)
    }

    private static func personMatte(cgImage: CGImage, extent: CGRect) -> CIImage? {
        func perform(_ request: VNGeneratePersonSegmentationRequest) -> CIImage? {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                OnlyPassersLog.vision.error(
                    "Person segmentation failed: \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
            guard let observation: VNPixelBufferObservation = VisionResults.observations(request).first else {
                return nil
            }
            return ImageAlign.aligned(CIImage(cvPixelBuffer: observation.pixelBuffer), to: extent)
        }

        let balanced = VNGeneratePersonSegmentationRequest()
        balanced.qualityLevel = .balanced
        balanced.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let matte = perform(balanced) {
            return matte
        }

        let fallback = VNGeneratePersonSegmentationRequest()
        fallback.qualityLevel = .balanced
        return perform(fallback)
    }

    private static func geometricMask(regions: [FaceOrPersonRegion], extent: CGRect) -> PasserbyMask? {
        let passersby = regions.filter { !$0.isMainSubject }
        guard !passersby.isEmpty else { return nil }
        let blobs = unionMask(passersby.map { SubjectGeometry.effectBox(for: $0) }, extent: extent)
        let subjects = regions.filter(\.isMainSubject)
        let punched = subjects.isEmpty
            ? blobs
            : punchOut(blobs, boxes: subjects.map { SubjectGeometry.protectionBox(for: $0) }, extent: extent)
        let feathered = feather(punched, radius: max(6, extent.width * 0.012), extent: extent)
        return PasserbyMask(image: feathered, source: .boundingBox, affectedCount: passersby.count)
    }

    private static func unionMask(_ unitBoxes: [CGRect], extent: CGRect) -> CIImage {
        var mask = CIImage(color: CIColor.black).cropped(to: extent)
        for box in unitBoxes {
            let rect = pixelRect(forTopLeftUnitBox: box, extent: extent)
            guard rect.width > 1, rect.height > 1 else { continue }
            let white = CIImage(color: CIColor.white).cropped(to: rect)
            mask = white.composited(over: mask)
        }
        return mask.cropped(to: extent)
    }

    /// 左上角归一化框 → Core Image 左下角像素矩形。
    private static func pixelRect(forTopLeftUnitBox box: CGRect, extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + box.minX * extent.width,
            y: extent.minY + (1 - box.maxY) * extent.height,
            width: box.width * extent.width,
            height: box.height * extent.height
        )
    }

    private static func punchOut(_ mask: CIImage, boxes: [CGRect], extent: CGRect) -> CIImage {
        let subject = unionMask(boxes, extent: extent)
        let black = CIImage(color: CIColor.black).cropped(to: extent)
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return mask }
        filter.setValue(black, forKey: kCIInputImageKey)
        filter.setValue(ImageAlign.aligned(mask, to: extent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(subject, forKey: kCIInputMaskImageKey)
        return (filter.outputImage ?? mask).cropped(to: extent)
    }

    private static func erode(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIMorphologyMinimum") else { return image.cropped(to: extent) }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return (filter.outputImage ?? image).cropped(to: extent)
    }

    private static func feather(_ image: CIImage, radius: CGFloat, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image.cropped(to: extent) }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return (filter.outputImage ?? image).cropped(to: extent)
    }
}

enum ImageAlign {
    static func aligned(_ image: CIImage, to extent: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 1,
              source.height > 1,
              extent.width > 1,
              extent.height > 1,
              source.width.isFinite,
              source.height.isFinite else {
            return CIImage(color: CIColor.black).cropped(to: extent)
        }

        let widthDelta = abs(source.width - extent.width)
        let heightDelta = abs(source.height - extent.height)
        if widthDelta <= 4, heightDelta <= 4 {
            let shift = CGAffineTransform(
                translationX: extent.minX - source.minX,
                y: extent.minY - source.minY
            )
            return image.transformed(by: shift).cropped(to: extent)
        }

        let scaleX = extent.width / source.width
        let scaleY = extent.height / source.height
        let transformed = image
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return transformed.cropped(to: extent)
    }

    static func lighten(_ primary: CIImage, _ secondary: CIImage, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CILightenBlendMode") else {
            return secondary.composited(over: primary).cropped(to: extent)
        }
        filter.setValue(aligned(primary, to: extent), forKey: kCIInputImageKey)
        filter.setValue(aligned(secondary, to: extent), forKey: kCIInputBackgroundImageKey)
        return (filter.outputImage ?? primary).cropped(to: extent)
    }

    static func blend(foreground: CIImage, background: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return background }
        filter.setValue(aligned(foreground, to: extent), forKey: kCIInputImageKey)
        filter.setValue(aligned(background, to: extent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(aligned(mask, to: extent), forKey: kCIInputMaskImageKey)
        return (filter.outputImage ?? background).cropped(to: extent)
    }
}

struct MaskPlan {
    var passerbyLabels: [Int]
    var unmatchedPasserbyRegions: [FaceOrPersonRegion]
    /// 每个主体区域都对上了一个实例。对上了就信任蒙版，不再用矩形挖主体。
    var matchedAllSubjects: Bool
}

enum MaskAssignment {
    static func plan(
        regions: [FaceOrPersonRegion],
        instanceBoxes: [Int: CGRect],
        labelAt: (CGPoint) -> Int
    ) -> MaskPlan {
        var subjectLabels = Set<Int>()
        var claimedSubjectIndexes = Set<Int>()

        for (index, region) in regions.enumerated() where region.isMainSubject {
            var protected = false
            let center = CGPoint(x: region.boundingBox.midX, y: region.boundingBox.midY)
            let centerLabel = labelAt(center)
            if centerLabel != 0 {
                subjectLabels.insert(centerLabel)
                protected = true
            }

            var bestLabel = 0
            var bestScore: CGFloat = 0
            for (label, box) in instanceBoxes {
                let score = SubjectGeometry.matchScore(region.boundingBox, box)
                if score > bestScore {
                    bestScore = score
                    bestLabel = label
                }
            }
            // 中心点和重合度最高的实例都保住。重叠时宁可多留一个路人清晰，也不要卡通到主体。
            if bestLabel != 0, bestScore >= 0.2 {
                subjectLabels.insert(bestLabel)
                protected = true
            }
            if protected {
                claimedSubjectIndexes.insert(index)
            }
        }

        var pairs: [(regionIndex: Int, label: Int, score: CGFloat)] = []
        for (index, region) in regions.enumerated() where !region.isMainSubject {
            for (label, box) in instanceBoxes where !subjectLabels.contains(label) {
                let score = SubjectGeometry.matchScore(region.boundingBox, box)
                if score >= 0.2 {
                    pairs.append((index, label, score))
                }
            }
        }
        pairs.sort { $0.score > $1.score }

        var usedRegions = claimedSubjectIndexes
        var usedLabels = subjectLabels
        var passerbyLabels = Set<Int>()
        for pair in pairs {
            if usedRegions.contains(pair.regionIndex) || usedLabels.contains(pair.label) { continue }
            usedRegions.insert(pair.regionIndex)
            usedLabels.insert(pair.label)
            passerbyLabels.insert(pair.label)
        }

        for label in instanceBoxes.keys where !subjectLabels.contains(label) && !passerbyLabels.contains(label) {
            passerbyLabels.insert(label)
        }

        let unmatchedPassersby = regions.enumerated().compactMap { index, region -> FaceOrPersonRegion? in
            guard !region.isMainSubject, !usedRegions.contains(index) else { return nil }
            return region
        }
        let subjectCount = regions.filter(\.isMainSubject).count
        return MaskPlan(
            passerbyLabels: passerbyLabels.sorted(),
            unmatchedPasserbyRegions: unmatchedPassersby,
            matchedAllSubjects: claimedSubjectIndexes.count == subjectCount
        )
    }
}

/// `instanceMask` 是低分辨率标签图：0 是背景，其它值是实例编号。第 0 行是转正后画面的顶部。
struct InstanceMaskMap {
    var width: Int
    var height: Int
    var labels: [UInt8]
    var boxes: [Int: CGRect]

    init?(buffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 1, height > 1 else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let knownFloat = format == kCVPixelFormatType_OneComponent32Float
            || format == kCVPixelFormatType_DepthFloat32
            || format == kCVPixelFormatType_DisparityFloat32
        let knownByte = format == kCVPixelFormatType_OneComponent8
        // 行宽对齐后，8-bit 标签图的 bytesPerRow 通常小于 width*2；float 则至少 4 字节一像素。
        let readAsFloat = knownFloat || (!knownByte && bytesPerRow >= width * MemoryLayout<Float>.size)
        guard knownFloat || knownByte || bytesPerRow >= width else {
            OnlyPassersLog.vision.error("Unexpected instance mask format: \(Int(format), privacy: .public)")
            return nil
        }
        if !knownFloat && !knownByte {
            OnlyPassersLog.vision.error("Guessing instance mask layout for format \(Int(format), privacy: .public)")
        }

        var packed = [UInt8](repeating: 0, count: width * height)
        if readAsFloat {
            guard bytesPerRow >= width * MemoryLayout<Float>.size else { return nil }
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    packed[y * width + x] = UInt8(clamping: Int(row[x].rounded()))
                }
            }
        } else {
            guard bytesPerRow >= width else { return nil }
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    packed[y * width + x] = row[x]
                }
            }
        }

        self.width = width
        self.height = height
        self.labels = packed
        self.boxes = Self.boxes(from: packed, width: width, height: height)
    }

    func label(atTopLeft point: CGPoint) -> Int {
        guard width > 1, height > 1 else { return 0 }
        let x = min(max(Int((point.x * CGFloat(width - 1)).rounded()), 0), width - 1)
        let y = min(max(Int((point.y * CGFloat(height - 1)).rounded()), 0), height - 1)
        return Int(labels[y * width + x])
    }

    private static func boxes(from labels: [UInt8], width: Int, height: Int) -> [Int: CGRect] {
        struct Accumulator {
            var minX: Int
            var minY: Int
            var maxX: Int
            var maxY: Int
        }

        var acc: [Int: Accumulator] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let label = Int(labels[y * width + x])
                guard label != 0 else { continue }
                if var existing = acc[label] {
                    existing.minX = min(existing.minX, x)
                    existing.minY = min(existing.minY, y)
                    existing.maxX = max(existing.maxX, x)
                    existing.maxY = max(existing.maxY, y)
                    acc[label] = existing
                } else {
                    acc[label] = Accumulator(minX: x, minY: y, maxX: x, maxY: y)
                }
            }
        }

        var boxes: [Int: CGRect] = [:]
        let widthF = CGFloat(width)
        let heightF = CGFloat(height)
        for (label, item) in acc {
            let rect = CGRect(
                x: CGFloat(item.minX) / widthF,
                y: CGFloat(item.minY) / heightF,
                width: CGFloat(item.maxX - item.minX + 1) / widthF,
                height: CGFloat(item.maxY - item.minY + 1) / heightF
            ).clampedToUnitSquare()
            guard rect.width >= 0.008, rect.height >= 0.012, rect.width * rect.height >= 0.00008 else {
                continue
            }
            boxes[label] = rect
        }
        return boxes
    }
}
