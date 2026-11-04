import CoreGraphics
import Foundation

/// 用户没有点选主体时，挑一个默认的主视角 / 自己。
///
/// 1. 只有一个区域时，那个人就是主体。
/// 2. 否则给人脸框和每个人物 / 人脸区域打分：`SubjectGeometry.prominence`。
/// 3. 最高分若是人脸，并且落在某个人物框里，主体是那个人物（整个人保持清晰）。
/// 4. 最高分若是一个区域，主体就是那个区域。
/// 5. 用户点选之后不要再调用这里，点选结果写在 `isMainSubject` 上。
enum SubjectSelection {
    static func applyDefault(
        to regions: [FaceOrPersonRegion],
        faceBoxes: [CGRect] = []
    ) -> [FaceOrPersonRegion] {
        guard !regions.isEmpty else { return [] }
        let subjectID = chosenSubjectID(in: regions, faceBoxes: faceBoxes)
        return regions.map { region in
            var copy = region
            copy.isMainSubject = region.id == subjectID
            return copy
        }
    }

    private static func chosenSubjectID(
        in regions: [FaceOrPersonRegion],
        faceBoxes: [CGRect]
    ) -> UUID {
        if regions.count == 1 {
            return regions[0].id
        }

        var candidates: [SubjectCandidate] = regions.map { .region($0.id, $0.boundingBox) }
        candidates.append(contentsOf: faceBoxes.map { .face($0) })

        guard let winner = candidates.max(by: { lhs, rhs in
            SubjectGeometry.prominence(of: lhs.box) < SubjectGeometry.prominence(of: rhs.box)
        }) else {
            return regions[0].id
        }

        switch winner {
        case .region(let id, _):
            return id
        case .face(let face):
            if let personID = containingPerson(for: face, in: regions) {
                return personID
            }
            if let faceID = matchingFaceRegion(face, in: regions) {
                return faceID
            }
            return bestRegionID(in: regions)
        }
    }

    private static func containingPerson(for face: CGRect, in regions: [FaceOrPersonRegion]) -> UUID? {
        let center = CGPoint(x: face.midX, y: face.midY)
        let hits = regions.filter { region in
            region.kind == .person && (
                SubjectGeometry.contains(region.boundingBox, point: center, slop: 0.02)
                    || SubjectGeometry.overlapRatio(face, region.boundingBox) > 0.5
            )
        }
        return hits.max { lhs, rhs in
            SubjectGeometry.overlapRatio(face, lhs.boundingBox)
                < SubjectGeometry.overlapRatio(face, rhs.boundingBox)
        }?.id
    }

    private static func matchingFaceRegion(_ face: CGRect, in regions: [FaceOrPersonRegion]) -> UUID? {
        let faces = regions.filter { $0.kind == .face }
        guard let best = faces.max(by: { lhs, rhs in
            SubjectGeometry.intersectionOverUnion(lhs.boundingBox, face)
                < SubjectGeometry.intersectionOverUnion(rhs.boundingBox, face)
        }) else {
            return nil
        }
        guard SubjectGeometry.intersectionOverUnion(best.boundingBox, face) > 0.3 else { return nil }
        return best.id
    }

    private static func bestRegionID(in regions: [FaceOrPersonRegion]) -> UUID {
        regions.max { lhs, rhs in
            SubjectGeometry.prominence(of: lhs.boundingBox) < SubjectGeometry.prominence(of: rhs.boundingBox)
        }?.id ?? regions[0].id
    }
}

private enum SubjectCandidate {
    case region(UUID, CGRect)
    case face(CGRect)

    var box: CGRect {
        switch self {
        case .region(_, let rect), .face(let rect):
            rect
        }
    }
}
