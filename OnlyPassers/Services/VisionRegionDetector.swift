import CoreGraphics
import Foundation
import Vision
import os

enum OnlyPassersLog {
    static let vision = Logger(subsystem: "com.ytyisme.OnlyPassers", category: "vision")
}

/// 端侧人物 / 人脸检测。坐标在返回前已换成左上角归一化。
///
/// 一个人一个框，方便预览里点选：
/// 1. `VNGeneratePersonInstanceMaskRequest` 的实例外接框（人物）
/// 2. 没被盖住的 `VNDetectHumanRectanglesRequest` 人体框
/// 3. 再没有落点的 `VNDetectFaceRectanglesRequest` 人脸框
///
/// 实例蒙版一次大约四个人。多出来的人若能被人体框或人脸框看到，仍会出现在列表里。
/// 默认主体由 `SubjectSelection` 标好，界面可以改 `isMainSubject`。
struct VisionRegionDetector: RegionDetecting {
    var maxPixelDimension: CGFloat = PhotoLimits.maxPixelDimension

    func detectRegions(in imageData: Data) async throws -> [FaceOrPersonRegion] {
        let maxPixel = maxPixelDimension
        return try await Task.detached(priority: .userInitiated) {
            let cgImage = try ImageCoding.uprightCGImage(from: imageData, maxPixel: maxPixel)
            return Self.detect(in: cgImage)
        }.value
    }

    static func detect(in cgImage: CGImage) -> [FaceOrPersonRegion] {
        let facesAndBodies = detectFacesAndHumans(in: cgImage)
        let instanceBoxes = detectInstanceBoxes(in: cgImage)

        var regions: [FaceOrPersonRegion] = []
        for box in instanceBoxes.values.sorted(by: { $0.midX < $1.midX }) {
            appendUnique(
                FaceOrPersonRegion(
                    id: UUID(),
                    kind: .person,
                    boundingBox: box,
                    isMainSubject: false,
                    confidence: 1
                ),
                to: &regions
            )
        }

        for human in facesAndBodies.humans {
            let box = SubjectGeometry.topLeft(fromVisionBottomLeft: human.boundingBox)
            guard isUsable(box) else { continue }
            appendUnique(
                FaceOrPersonRegion(
                    id: UUID(),
                    kind: .person,
                    boundingBox: box,
                    isMainSubject: false,
                    confidence: human.confidence
                ),
                to: &regions
            )
        }

        var faceBoxes: [CGRect] = []
        for face in facesAndBodies.faces {
            let box = SubjectGeometry.topLeft(fromVisionBottomLeft: face.boundingBox)
            guard isUsable(box) else { continue }
            faceBoxes.append(box)
            appendUnique(
                FaceOrPersonRegion(
                    id: UUID(),
                    kind: .face,
                    boundingBox: box,
                    isMainSubject: false,
                    confidence: face.confidence
                ),
                to: &regions
            )
        }

        let sorted = regions.sorted { lhs, rhs in
            let delta = lhs.boundingBox.midX - rhs.boundingBox.midX
            if abs(delta) > 0.015 { return delta < 0 }
            return lhs.boundingBox.midY < rhs.boundingBox.midY
        }
        return SubjectSelection.applyDefault(to: sorted, faceBoxes: faceBoxes)
    }

    private static func isUsable(_ box: CGRect) -> Bool {
        box.width >= 0.008 && box.height >= 0.012 && box.width * box.height >= 0.00008
    }

    private static func appendUnique(_ region: FaceOrPersonRegion, to regions: inout [FaceOrPersonRegion]) {
        let box = region.boundingBox
        let duplicate = regions.contains { existing in
            SubjectGeometry.intersectionOverUnion(existing.boundingBox, box) > 0.45
                || SubjectGeometry.overlapRatio(box, existing.boundingBox) > 0.6
        }
        if !duplicate {
            regions.append(region)
        }
    }

    private static func detectFacesAndHumans(
        in cgImage: CGImage
    ) -> (faces: [VNFaceObservation], humans: [VNHumanObservation]) {
        let faces = VNDetectFaceRectanglesRequest()
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([faces, humans])
            return (VisionResults.observations(faces), VisionResults.observations(humans))
        } catch {
            OnlyPassersLog.vision.error(
                "Combined face/human detection failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        let faceOnly = VNDetectFaceRectanglesRequest()
        var faceResults: [VNFaceObservation] = []
        do {
            let faceHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try faceHandler.perform([faceOnly])
            faceResults = VisionResults.observations(faceOnly)
        } catch {
            OnlyPassersLog.vision.error(
                "Face detection failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        let upper = VNDetectHumanRectanglesRequest()
        upper.upperBodyOnly = true
        var humanResults: [VNHumanObservation] = []
        do {
            let humanHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try humanHandler.perform([upper])
            humanResults = VisionResults.observations(upper)
        } catch {
            OnlyPassersLog.vision.error(
                "Human detection failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        return (faceResults, humanResults)
    }

    private static func detectInstanceBoxes(in cgImage: CGImage) -> [Int: CGRect] {
        let request = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            OnlyPassersLog.vision.error(
                "Person instance mask failed: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
        guard let observation: VNInstanceMaskObservation = VisionResults.observations(request).first else {
            return [:]
        }
        return InstanceMaskMap(buffer: observation.instanceMask)?.boxes ?? [:]
    }
}

enum VisionResults {
    static func observations<T: VNObservation>(_ request: VNRequest) -> [T] {
        (request.results ?? []).compactMap { $0 as? T }
    }
}
