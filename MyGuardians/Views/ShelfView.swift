import SwiftUI
import UIKit

struct ShelfView: View {
    @EnvironmentObject private var store: GuardianStore
    @State private var selection: Guardian?
    @State private var showInfo = false
    var goFind: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: OGLayout.sectionGap) {
            SketchHeader(title: "My shelf", titleAlignment: .leading,
                         trailingAsset: "screen-info", trailingAction: { showInfo = true },
                         trailingAccessibilityLabel: "About your shelf")
                .ogScreenHeader()
            if store.guardians.isEmpty {
                Spacer()
                Text("Nothing on your shelf yet!").font(OGType.section)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.guardians) { guardian in
                            Button { selection = guardian } label: {
                                SketchCard(content: VStack(spacing: 4) {
                                    GuardianArtwork(filename: guardian.drawingFile)
                                        .frame(height: 96)
                                        .frame(maxWidth: .infinity)
                                        .padding(.bottom, 8)
                                    Text(guardian.name)
                                        .font(OGType.section)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(guardian.objectName.isEmpty ? "Little guardian" : guardian.objectName)
                                        .font(OGType.caption)
                                        .foregroundColor(Color.ogInk.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 164))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(guardian.name), view profile")
                        }
                    }
                    .padding(.horizontal, OGLayout.screenMargin)
                    .padding(.bottom, 24)
                }
                .ogScrollBehindBottomControls()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SketchButton(label: store.guardians.isEmpty ? "Make a little friend" : "Make more friends",
                         prominent: true, action: goFind)
                .accessibilityIdentifier("shelf-find-guardian")
                .ogBottomAction(aboveNavigationBar: true)
        }
        .background(Color.ogBackground)
        .foregroundColor(Color.ogInk)
        .guardianProfileSheet(selection: $selection)
        .onAppear { showInfo = false }
        .onDisappear { showInfo = false }
        .alert("Your little collection", isPresented: $showInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Tap a guardian to see its memories, edit its name, or find it again with your camera.")
        }
    }
}

struct GuardianDetailView: View {
    @EnvironmentObject private var store: GuardianStore
    @Environment(\.dismiss) private var dismiss
    let guardianID: UUID
    private let onCaptureMemory: (() -> Void)?
    @State private var captureButtonBottomOffset: CGFloat = 0
    @State private var captureButtonHeight: CGFloat = OGLayout.primaryMinimumHeight
    @State private var showEdit = false
    @State private var selectedMemory: GuardianMemory?
    @State private var showDeleteConfirmation = false
    @State private var deletionIssue: String?

    init(guardianID: UUID, onCaptureMemory: (() -> Void)? = nil) {
        self.guardianID = guardianID
        self.onCaptureMemory = onCaptureMemory
    }

    var body: some View {
        NavigationStack {
            if let guardian = store.guardian(guardianID) {
                let memories = store.memories(for: guardianID)
                VStack(spacing: 0) {
                    profileHeader
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(spacing: 6) {
                                GuardianArtwork(filename: guardian.drawingFile)
                                    .frame(width: OGLayout.profileArtworkSize, height: OGLayout.profileArtworkSize)
                                    .scaleEffect(1.15)
                                Text(guardian.name)
                                    .font(OGType.title)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(guardian.objectName.isEmpty ? "An everyday little friend" : guardian.objectName)
                                    .font(OGType.body)
                                    .foregroundColor(Color.ogInk.opacity(0.6))
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .padding(.bottom, 20) // Together with the parent’s 16 pt spacing: 36 pt.

                            Text(memories.isEmpty ? "No memories yet." : "Little memories (\(memories.count))")
                                .font(OGType.section)
                                .frame(maxWidth: .infinity, alignment: .center)
                            if !memories.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(memories) { memory in
                                        Button { selectedMemory = memory } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                ZStack {
                                                    SketchOutline(radius: 12).fill(Color.ogPaper)
                                                    if let photo = store.image(memory.imageFile) {
                                                        GeometryReader { geometry in
                                                            Image(uiImage: photo)
                                                                .resizable()
                                                                .scaledToFill()
                                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                                                .clipShape(SketchOutline(radius: 12))
                                                        }
                                                    } else {
                                                        Text("Photo unavailable").font(OGType.caption)
                                                    }
                                                }
                                                .aspectRatio(1, contentMode: .fit)
                                                .overlay(SketchOutline(radius: 12).stroke(Color.ogInk, style: SketchInk.strokeStyle))
                                                .accessibilityIdentifier("profile-memory-photo-\(memory.id)")
                                                Text(memoryCaption(memory))
                                                    .font(OGType.caption)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 206, alignment: .topLeading)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Memory from \(memoryCaption(memory))")
                                        .accessibilityIdentifier("profile-memory-\(memory.id)")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, OGLayout.screenMargin)
                        .padding(.bottom, 16)
                    }
                    .ogScrollBehindBottomControls(
                        minimumBottomClearance: captureButtonHeight + OGLayout.profileBottomGap
                    )
                    .accessibilityIdentifier("profile-scroll")
                }
                .background(Color.ogBackground)
                .foregroundColor(Color.ogInk)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showEdit) { EditGuardianView(guardianID: guardianID) }
                .sheet(item: $selectedMemory) { MemoryDetailView(memory: $0) }
            } else {
                Text("This guardian was not found.")
                    .font(OGType.body)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .bottom) {
            if store.guardian(guardianID) != nil {
                ZStack(alignment: .bottom) {
                    WindowBottomEdgeAnchor { offset in
                        guard abs(offset - captureButtonBottomOffset) > 0.1 else { return }
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { captureButtonBottomOffset = offset }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    SketchButton(label: "Capture a memory", prominent: true) {
                        if let onCaptureMemory { onCaptureMemory() } else { dismiss() }
                    }
                    .accessibilityIdentifier("profile-capture")
                    .padding(.horizontal, OGLayout.screenMargin)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { captureButtonHeight = $0 }
                    .offset(y: captureButtonBottomOffset)
                }
                .background(Color.clear)
            }
        }
        .background(Color.ogBackground)
        .presentationBackground(Color.ogBackground)
        .presentationDetents([.fraction(0.88), .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .alert("Say goodbye to this guardian?", isPresented: $showDeleteConfirmation) {
            Button("Keep guardian", role: .cancel) {}
            Button("Delete guardian", role: .destructive) { deleteGuardian() }
        } message: {
            Text("This will delete the guardian and all its little memories. This can't be undone.")
        }
        .alert("Could not delete guardian", isPresented: Binding(
            get: { deletionIssue != nil },
            set: { if !$0 { deletionIssue = nil } }
        )) {
            Button("OK", role: .cancel) { deletionIssue = nil }
        } message: {
            Text(deletionIssue ?? "Please try again.")
        }
    }

    private func deleteGuardian() {
        do {
            try store.deleteGuardian(guardianID)
            finishDeletion()
        } catch let error as GuardianStore.DeletionError where error.guardianWasDeleted {
            finishDeletion(cleanupMessage: error.localizedDescription)
        } catch {
            deletionIssue = error.localizedDescription
        }
    }

    private func finishDeletion(cleanupMessage: String? = nil) {
        dismiss()
        var userInfo: [String: String] = [:]
        if let cleanupMessage { userInfo["cleanupMessage"] = cleanupMessage }
        NotificationCenter.default.post(name: .guardianDeleted, object: store, userInfo: userInfo)
    }

    private func memoryCaption(_ memory: GuardianMemory) -> String {
        let date = memory.takenAt.formatted(date: .abbreviated, time: .omitted)
        guard let location = memory.location, !location.isEmpty else { return date }
        return "\(date) · \(location)"
    }

    private var profileHeader: some View {
        HStack(spacing: 0) {
            profileButton("screen-back", label: "Back", identifier: "profile-back") { dismiss() }
            Spacer(minLength: 8)
            profileButton("profile-edit", label: "Edit guardian", identifier: "profile-edit") { showEdit = true }
            profileButton("profile-delete", label: "Delete guardian", identifier: "profile-delete") { showDeleteConfirmation = true }
            profileButton("screen-close", label: "Close", identifier: "profile-close") { dismiss() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.ogBackground)
    }

    private func profileButton(_ asset: String, label: String, identifier: String? = nil,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            profileIcon(asset)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? label)
    }

    private func profileIcon(_ asset: String) -> some View {
        Image(asset)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    #if DEBUG
    fileprivate static func deletionPreview(guardianID: UUID) -> Self {
        var view = Self(guardianID: guardianID)
        view._showDeleteConfirmation = State(initialValue: true)
        return view
    }
    #endif
}

private struct EditGuardianView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GuardianStore
    let guardianID: UUID
    @State private var name = ""
    @State private var object = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SketchHeader(title: "Edit guardian", onBack: { dismiss() }, titleFont: OGType.section)
                SketchField(label: "Guardian name", text: $name)
                SketchField(label: "Object (optional)", text: $object)
                SketchButton(label: "Save changes", prominent: true) {
                    store.renameGuardian(guardianID, name: name, objectName: object)
                    dismiss()
                }
            }
            .padding(24)
        }
        .background(Color.ogBackground)
        .presentationBackground(Color.ogBackground)
        .foregroundColor(Color.ogInk)
        .onAppear {
            if let guardian = store.guardian(guardianID) {
                name = guardian.name
                object = guardian.objectName
            }
        }
    }
}

private struct MemoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GuardianStore
    let memory: GuardianMemory
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OGLayout.sectionGap) {
                SketchHeader(title: "A little memory", onBack: { dismiss() }, titleFont: OGType.section)
                if let image = store.image(memory.imageFile) {
                    Image(uiImage:image).resizable().scaledToFit()
                        .background(SketchOutline().fill(Color.ogPaper))
                        .overlay(SketchOutline().stroke(Color.ogInk, style: SketchInk.strokeStyle))
                }
                Text(memory.takenAt.formatted(date:.complete,time:.shortened))
                    .font(OGType.body)
                if let location = memory.location {
                    Text("Location: \(location)").font(OGType.body)
                }
                if let note = memory.note, !note.isEmpty {
                    Text(note).font(OGType.body)
                }
            }
            .padding(24)
        }
        .background(Color.ogBackground)
        .presentationBackground(Color.ogBackground)
        .foregroundColor(Color.ogInk)
    }
}

#if DEBUG
#Preview("Shelf · Collection") {
    ShelfScreenPreview(screen: .shelf)
}

#Preview("Shelf · Empty") {
    ShelfScreenPreview(screen: .shelf, occupied: false)
}

#Preview("Guardian Profile") {
    ShelfScreenPreview(screen: .profile)
}

#Preview("Guardian Profile · No memories") {
    ShelfScreenPreview(screen: .profileEmpty)
}

#Preview("Guardian Profile · Delete confirmation") {
    ShelfScreenPreview(screen: .deleteConfirmation)
}

#Preview("Edit Guardian") {
    ShelfScreenPreview(screen: .edit)
}

#Preview("Memory Detail") {
    ShelfScreenPreview(screen: .memory)
}

#Preview("Shelf · Larger Text") {
    ShelfScreenPreview(screen: .shelf)
        .environment(\.dynamicTypeSize, .accessibility3)
}

@MainActor
private struct ShelfScreenPreview: View {
    enum Screen { case shelf, profile, profileEmpty, deleteConfirmation, edit, memory }

    @StateObject private var store: GuardianStore
    @State private var showProfile = true
    let screen: Screen
    private let guardianID: UUID?
    private let memory: GuardianMemory?

    init(screen: Screen, occupied: Bool = true) {
        let store = HomePreviewFixtures.makeStore(occupied: occupied)
        if occupied {
            for (index, name) in ["Pip", "Daisy", "June"].enumerated() {
                HomePreviewFixtures.addSampleGuardian(to: store, name: name, variant: index)
            }
        }
        let guardian = store.guardians.first
        var firstMemory: GuardianMemory?
        if screen != .profileEmpty, let guardian, let image = store.drawing(for: guardian) {
            firstMemory = store.addMemory(guardianID: guardian.id, image: image,
                                          location: "At home", note: "A little everyday magic.")
            store.addMemory(guardianID: guardian.id, image: image, location: nil, note: nil)
        }
        self.screen = screen
        self.guardianID = guardian?.id
        self.memory = firstMemory
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        Group {
            switch screen {
            case .shelf:
                ShelfView(goFind: {})
            case .profile, .profileEmpty:
                ShelfView(goFind: {})
                    .sheet(isPresented: $showProfile) {
                        if let guardianID { GuardianDetailView(guardianID: guardianID) }
                    }
            case .deleteConfirmation:
                if let guardianID { GuardianDetailView.deletionPreview(guardianID: guardianID) }
            case .edit:
                if let guardianID { EditGuardianView(guardianID: guardianID) }
            case .memory:
                if let memory { MemoryDetailView(memory: memory) }
            }
        }
        .environmentObject(store)
        .font(OGType.body)
        .preferredColorScheme(.light)
        .background(Color.ogBackground)
    }
}
#endif

// Open recognition only after the profile's native downward dismissal completes.
private struct GuardianProfilePresentation: ViewModifier {
    @EnvironmentObject private var store: GuardianStore
    @Binding var selection: Guardian?
    @State private var pendingGuardianID: UUID?

    func body(content: Content) -> some View {
        content.sheet(item: $selection, onDismiss: {
            guard let guardianID = pendingGuardianID else { return }
            pendingGuardianID = nil
            NotificationCenter.default.post(name: .guardianRecognitionRequested, object: store,
                                            userInfo: ["guardianID": guardianID])
        }) { guardian in
            GuardianDetailView(guardianID: guardian.id, onCaptureMemory: {
                pendingGuardianID = guardian.id
                selection = nil
            })
            .environmentObject(store)
        }
    }
}

extension View {
    func guardianProfileSheet(selection: Binding<Guardian?>) -> some View {
        modifier(GuardianProfilePresentation(selection: selection))
    }
}
