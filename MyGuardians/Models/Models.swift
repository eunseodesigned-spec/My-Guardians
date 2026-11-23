import Foundation
import UIKit

struct Guardian: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var objectName: String
    var createdAt: Date
    var drawingFile: String
    var strokesFile: String
    var referenceFile: String
    var motionSeed: Double

    static func == (lhs: Guardian, rhs: Guardian) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct GuardianMemory: Codable, Identifiable {
    var id: UUID
    var guardianID: UUID
    var imageFile: String
    var takenAt: Date
    var location: String?
    var note: String?
}

struct MemoryDraft: Identifiable {
    var id = UUID()
    var guardianID: UUID
    var composite: UIImage
}

struct CreationDraft: Identifiable {
    var id = UUID()
    var reference: UIImage
}

struct RecognizedGuardian: Equatable {
    var guardianID: UUID
    var distance: Float
}
