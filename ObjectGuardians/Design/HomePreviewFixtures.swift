#if DEBUG
import UIKit
import PencilKit

/// Isolated sample catalogs for SwiftUI previews; never reads or changes saved app data.
@MainActor
enum HomePreviewFixtures {
    static func makeStore(occupied: Bool) -> GuardianStore {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ObjectGuardians-HomePreview-\(UUID().uuidString)", isDirectory: true)
        let store = GuardianStore(storageFolder: folder)
        if occupied {
            for (index, name) in ["Bean", "Button", "Moss"].enumerated() {
                addSampleGuardian(to: store, name: name, variant: index)
            }
        }
        return store
    }

    /// Goes through the same combined-artwork save path used by guardian creation.
    @discardableResult
    static func addSampleGuardian(to store: GuardianStore, name: String = "Bean", variant: Int = 0) -> Guardian {
        let size = CGSize(width: 144, height: 168)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let object = renderer.image { _ in
            let colors = [
                UIColor(red: 0.91, green: 0.84, blue: 0.66, alpha: 1),
                UIColor(red: 0.97, green: 0.94, blue: 0.66, alpha: 1),
                UIColor(red: 0.74, green: 0.82, blue: 0.67, alpha: 1)
            ]
            UIColor.black.setStroke()
            let handle = UIBezierPath(ovalIn: CGRect(x: 96, y: 42, width: 31, height: 49))
            handle.lineWidth = 3
            handle.stroke()
            let cup = UIBezierPath(roundedRect: CGRect(x: 22, y: 37, width: 79, height: 94), cornerRadius: 13)
            colors[abs(variant) % colors.count].setFill()
            cup.fill()
            cup.lineWidth = 2.5
            cup.stroke()
            let rim = UIBezierPath(ovalIn: CGRect(x: 23, y: 33, width: 77, height: 12))
            colors[abs(variant) % colors.count].setFill()
            rim.fill()
            rim.lineWidth = 2
            rim.stroke()
        }
        let ink = renderer.image { _ in
            UIColor.black.setFill()
            UIColor.black.setStroke()
            UIBezierPath(ovalIn: CGRect(x: 43, y: 68, width: 5, height: 7)).fill()
            UIBezierPath(ovalIn: CGRect(x: 75, y: 68, width: 5, height: 7)).fill()
            let smile = UIBezierPath()
            smile.move(to: CGPoint(x: 50, y: 87))
            smile.addQuadCurve(to: CGPoint(x: 75, y: 87), controlPoint: CGPoint(x: 63, y: 101))
            smile.lineWidth = 2.5
            smile.lineCapStyle = .round
            smile.stroke()
            let feet = UIBezierPath()
            feet.move(to: CGPoint(x: 43, y: 129))
            feet.addLine(to: CGPoint(x: 38, y: 146))
            feet.move(to: CGPoint(x: 79, y: 129))
            feet.addLine(to: CGPoint(x: 85, y: 146))
            feet.lineWidth = 2.5
            feet.lineCapStyle = .round
            feet.stroke()
        }
        let combined = renderer.image { _ in
            object.draw(at: .zero)
            ink.draw(at: .zero)
        }
        let reference = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            object.draw(at: .zero)
        }
        guard let guardian = store.addGuardian(
            name: name,
            objectName: "Mug",
            reference: reference,
            drawing: PKDrawing(),
            drawingImage: combined,
            inkImage: ink,
            cutoutImage: object
        ) else {
            preconditionFailure("Could not prepare the isolated Home preview")
        }
        return guardian
    }
}
#endif
