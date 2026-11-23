import Foundation
import UIKit
import PencilKit

@MainActor
final class GuardianStore: ObservableObject {
    @Published private(set) var guardians: [Guardian] = []
    @Published private(set) var memories: [GuardianMemory] = []

    private struct Catalog: Codable {
        var guardians: [Guardian]
        var memories: [GuardianMemory]
    }

    private let folder: URL

    enum DeletionError: LocalizedError {
        // The catalog has already been committed. The profile must dismiss even
        // if a damaged or temporarily unavailable file needs a later retry.
        case cleanupPending(underlying: Error)

        var guardianWasDeleted: Bool { true }

        var errorDescription: String? {
            "The guardian was deleted, but some local files could not be removed. Cleanup will retry when the app opens again."
        }
    }

    init(storageFolder: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = storageFolder ?? documents.appendingPathComponent("ObjectGuardians", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if load() {
            do { try finishPendingDeletions() }
            catch { print("Could not finish guardian file cleanup: \(error)") }
        }
    }

    private var catalogURL: URL { folder.appendingPathComponent("catalog.json") }
    private var pendingDeletionURL: URL {
        folder.appendingPathComponent(".pending-guardian-deletions.json")
    }

    @discardableResult
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return false }
        guardians = catalog.guardians
        memories = catalog.memories
        return true
    }

    private func persist() {
        let catalog = Catalog(guardians: guardians, memories: memories)
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        do { try data.write(to: catalogURL, options: .atomic) }
        catch { print("Could not persist catalog: \(error)") }
    }

    func image(_ name: String) -> UIImage? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return UIImage(data: data)
    }

    // The saved artwork displayed in Home and Shelf (object + ink).
    func drawing(for guardian: Guardian) -> UIImage? { image(guardian.drawingFile) }

    // Ink-only overlay for the live camera, so the real object isn't doubled.
    // Legacy guardians didn't have a separate overlay: their original
    // drawingFile already contains ink only.
    func overlay(for guardian: Guardian) -> UIImage? {
        image("\(guardian.id.uuidString)-ink.png") ?? drawing(for: guardian)
    }

    func cutout(for guardian: Guardian) -> UIImage? {
        image("\(guardian.id.uuidString)-object.png")
    }
    func reference(for guardian: Guardian) -> UIImage? { image(guardian.referenceFile) }

    func guardian(_ id: UUID) -> Guardian? { guardians.first { $0.id == id } }
    func memories(for id: UUID) -> [GuardianMemory] {
        memories.filter { $0.guardianID == id }.sorted { $0.takenAt > $1.takenAt }
    }

    @discardableResult
    func addGuardian(name: String, objectName: String, reference: UIImage, drawing: PKDrawing,
                     drawingImage: UIImage, inkImage: UIImage, cutoutImage: UIImage) -> Guardian? {
        let id = UUID()
        let prefix = id.uuidString
        let referenceFile = "\(prefix)-reference.jpg"
        let drawingFile = "\(prefix)-guardian.png"  // combined object + ink
        let inkFile = "\(prefix)-ink.png"
        let cutoutFile = "\(prefix)-object.png"
        let strokesFile = "\(prefix)-strokes.data"
        guard let originalData = reference.jpegData(compressionQuality: 0.82),
              let pngData = drawingImage.pngData(),
              let inkData = inkImage.pngData(),
              let objectData = cutoutImage.pngData() else { return nil }
        do {
            try originalData.write(to: folder.appendingPathComponent(referenceFile), options: .atomic)
            try pngData.write(to: folder.appendingPathComponent(drawingFile), options: .atomic)
            try inkData.write(to: folder.appendingPathComponent(inkFile), options: .atomic)
            try objectData.write(to: folder.appendingPathComponent(cutoutFile), options: .atomic)
            try drawing.dataRepresentation().write(to: folder.appendingPathComponent(strokesFile), options: .atomic)
        } catch {
            print("Failed to save guardian files: \(error)")
            return nil
        }
        let saved = Guardian(id: id, name: name, objectName: objectName, createdAt: Date(),
                             drawingFile: drawingFile, strokesFile: strokesFile,
                             referenceFile: referenceFile, motionSeed: Double.random(in: 0 ... 100))
        guardians.append(saved)
        persist()
        return saved
    }

    @discardableResult
    func addMemory(guardianID: UUID, image: UIImage, location: String?, note: String?) -> GuardianMemory? {
        let id = UUID()
        let filename = "\(id.uuidString)-memory.jpg"
        guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
        do { try data.write(to: folder.appendingPathComponent(filename), options: .atomic) }
        catch { return nil }
        let memory = GuardianMemory(id: id, guardianID: guardianID, imageFile: filename,
                                    takenAt: Date(), location: location, note: note)
        memories.append(memory)
        persist()
        return memory
    }

    func renameGuardian(_ id: UUID, name: String, objectName: String) {
        guard let i = guardians.firstIndex(where: { $0.id == id }) else { return }
        guardians[i].name = name
        guardians[i].objectName = objectName
        persist()
    }

    /// Removes the catalog entry first, then unreferenced artwork and memories.
    /// A catalog-write error leaves the published collection and its files intact.
    func deleteGuardian(_ id: UUID) throws {
        let removedGuardians = guardians.filter { $0.id == id }
        let removedMemories = memories.filter { $0.guardianID == id }
        guard !removedGuardians.isEmpty || !removedMemories.isEmpty else { return }

        let remainingGuardians = guardians.filter { $0.id != id }
        let remainingMemories = memories.filter { $0.guardianID != id }
        let catalog = Catalog(guardians: remainingGuardians, memories: remainingMemories)
        let data = try JSONEncoder().encode(catalog)
        let previousPending = try pendingDeletionNames()
        let removedFiles = referencedFiles(guardians: removedGuardians, memories: removedMemories)

        // The journal precedes the atomic catalog commit. On interruption, load
        // protects every file still referenced by the catalog before retrying.
        try writePendingDeletionNames(previousPending.union(removedFiles))
        do { try data.write(to: catalogURL, options: .atomic) }
        catch {
            do { try writePendingDeletionNames(previousPending) }
            catch { print("Could not restore guardian cleanup journal: \(error)") }
            throw error
        }

        guardians = remainingGuardians
        memories = remainingMemories
        do { try finishPendingDeletions() }
        catch { throw DeletionError.cleanupPending(underlying: error) }
    }

    private func referencedFiles(guardians: [Guardian], memories: [GuardianMemory]) -> Set<String> {
        var names = Set(memories.map(\.imageFile))
        for guardian in guardians {
            names.formUnion([guardian.referenceFile, guardian.drawingFile, guardian.strokesFile,
                             "\(guardian.id.uuidString)-ink.png", "\(guardian.id.uuidString)-object.png"])
        }
        return names
    }

    private func pendingDeletionNames() throws -> Set<String> {
        do {
            let data = try Data(contentsOf: pendingDeletionURL)
            return Set(try JSONDecoder().decode([String].self, from: data))
        } catch where isMissingFile(error) {
            return []
        }
    }

    private func writePendingDeletionNames(_ names: Set<String>) throws {
        if names.isEmpty {
            do { try FileManager.default.removeItem(at: pendingDeletionURL) }
            catch where isMissingFile(error) { }
        } else {
            let data = try JSONEncoder().encode(names.sorted())
            try data.write(to: pendingDeletionURL, options: .atomic)
        }
    }

    private func finishPendingDeletions() throws {
        let pending = try pendingDeletionNames()
        guard !pending.isEmpty else { return }
        let protectedNames = referencedFiles(guardians: guardians, memories: memories)
        // Compare resolved paths as well as names, so aliases cannot remove a
        // file referenced by another guardian or one of its memories.
        let protectedPaths = Set(protectedNames.compactMap {
            try? managedDeletionURL(for: $0).resolvingSymlinksInPath().path
        })
        var retry: Set<String> = []
        var firstFailure: Error?
        for name in pending.sorted() where !protectedNames.contains(name) {
            do {
                let url = try managedDeletionURL(for: name)
                guard !protectedPaths.contains(url.resolvingSymlinksInPath().path) else { continue }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let type = attributes[.type] as? FileAttributeType
                guard type == .typeRegular || type == .typeSymbolicLink else {
                    throw NSError(domain: "GuardianStore.FileCleanup", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Refused to remove a folder at \(name)."])
                }
                try FileManager.default.removeItem(at: url)
            } catch where isMissingFile(error) {
                // Already removed, including after an interrupted cleanup.
            } catch {
                retry.insert(name)
                firstFailure = firstFailure ?? error
            }
        }
        try writePendingDeletionNames(retry)
        if let firstFailure { throw firstFailure }
    }

    private func managedDeletionURL(for name: String) throws -> URL {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        let url = folder.appendingPathComponent(name).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        let reserved = [catalogURL, pendingDeletionURL].map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        }
        guard !name.isEmpty, !(name as NSString).isAbsolutePath,
              resolved.path.hasPrefix(root.path + "/"), !reserved.contains(resolved.path) else {
            throw NSError(domain: "GuardianStore.FileCleanup", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Refused to remove a file outside guardian artwork storage or a reserved storage file."])
        }
        return url
    }

    private func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
    }
}
