import SwiftUI
import UIKit

struct SaveMemoryView: View {
    @EnvironmentObject private var store: GuardianStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = OptionalLocation()
    let draft: MemoryDraft
    var onSaved: () -> Void
    @State private var note = ""
    @State private var issue: String?
    @State private var showInfo = false
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(spacing: OGLayout.gap) {
            SketchHeader(
                title: "Keep this little moment", onBack: { dismiss() },
                trailingAsset: "screen-close", trailingAction: { showInfo = true },
                trailingAccessibilityLabel: "About saving a memory", titleFont: OGType.section
            )
            .simultaneousGesture(TapGesture().onEnded { noteIsFocused = false })
            .alert("Keep this little moment", isPresented: $showInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(
                    "The date is added automatically. You can add your location and a note before saving this memory to your guardian."
                )
            }
            .ogScreenHeader()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: OGLayout.sectionGap) {

                        ZStack {
                            SketchOutline(radius: 14).fill(Color.ogPaper)
                            GeometryReader { canvas in
                                Image(uiImage: draft.composite)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: canvas.size.width, height: canvas.size.height)
                                    .clipShape(SketchOutline(radius: 14))
                            }
                        }
                        .frame(
                            height: max(
                                OGLayout.minimumCanvasHeight,
                                geometry.size.height - OGLayout.memoryMetadataHeight)
                        )
                        .overlay(SketchOutline(radius: 14).stroke(Color.ogInk, style: SketchInk.strokeStyle))
                        .accessibilityLabel("Memory photo preview")
                        .onTapGesture { noteIsFocused = false }

                        HStack(spacing: 16) {
                            metadataIcon("memory-calendar")
                            Text(Date().formatted(date: .abbreviated, time: .shortened))
                                .font(OGType.body)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)

                        Button {
                            location.ask()
                        } label: {
                            HStack(spacing: 16) {
                                metadataIcon("memory-location")
                                Text(location.value ?? location.status)
                                    .font(OGType.body)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Optionally attach your current location")

                        TextEditor(text: $note)
                            .focused($noteIsFocused)
                            .font(OGType.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 110)
                            .background(SketchOutline(radius: 12).fill(Color.ogPaper))
                            .overlay(SketchOutline(radius: 12).stroke(Color.ogInk, style: SketchInk.strokeStyle))
                            .overlay(alignment: .topLeading) {
                                if note.isEmpty {
                                    Text("What made today special?")
                                        .font(OGType.body)
                                        .foregroundColor(Color.ogInk.opacity(0.5))
                                        .padding(.leading, 16)
                                        .padding(.top, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityLabel("Note (optional)")

                    }
                    .padding(.horizontal, OGLayout.screenMargin)
                    .padding(.bottom, OGLayout.gap)
                }
                .ogScrollBehindBottomControls()
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveAction.ogBottomAction()
        }
        .background(Color.ogBackground)
        .presentationBackground(Color.ogBackground)
        .foregroundColor(Color.ogInk)
        .onAppear { showInfo = false }
        .onDisappear { showInfo = false }
        .alert("Could not save", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
            Button("OK", role: .cancel) { issue = nil }
        } message: {
            Text(issue ?? "")
        }
    }

    private var saveAction: some View {
        SketchButton(label: "Save memory", prominent: true) {
            if store.addMemory(
                guardianID: draft.guardianID, image: draft.composite,
                location: location.value,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            {
                onSaved()
            } else {
                issue = "Please try again."
            }
        }
        .accessibilityIdentifier("memory-save")
    }

    private func metadataIcon(_ asset: String) -> some View {
        Image(asset)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Save Memory") {
    SaveMemoryScreenPreview()
}

#Preview("Save Memory · Larger Text") {
    SaveMemoryScreenPreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}

@MainActor
private struct SaveMemoryScreenPreview: View {
    @StateObject private var store: GuardianStore
    private let draft: MemoryDraft

    init() {
        let store = HomePreviewFixtures.makeStore(occupied: true)
        guard let guardian = store.guardians.first,
              let image = store.drawing(for: guardian) else {
            preconditionFailure("Could not prepare the isolated memory preview")
        }
        draft = MemoryDraft(guardianID: guardian.id, composite: image)
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        SaveMemoryView(draft: draft, onSaved: {})
            .environmentObject(store)
            .font(OGType.body)
            .preferredColorScheme(.light)
    }
}
#endif
