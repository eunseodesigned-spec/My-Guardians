import Foundation
import UIKit
import Vision

/// Best-effort image similarity. This is NOT a 3D object-recognition or AR-anchor engine.
/// Use distinctive, well-lit objects and repeat the registration angle for a demo.
final class VisionMatcher {
    private var known: [(UUID, VNFeaturePrintObservation)] = []

    func update(_ references: [(UUID, UIImage)]) {
        known = references.compactMap { id, image in
            guard let feature = Self.featurePrint(for: image) else { return nil }
            return (id, feature)
        }
    }

    static func featurePrint(for image: UIImage) -> VNFeaturePrintObservation? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .centerCrop
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch { return nil }
    }

    func closest(to image: UIImage) -> RecognizedGuardian? {
        guard let feature = Self.featurePrint(for: image) else { return nil }
        var closest: RecognizedGuardian?
        for (id, knownFeature) in known {
            var dist: Float = .greatestFiniteMagnitude
            do { try knownFeature.computeDistance(&dist, to: feature) }
            catch { continue }
            if closest == nil || dist < closest!.distance { closest = .init(guardianID: id, distance: dist) }
        }
        return closest
    }
}
