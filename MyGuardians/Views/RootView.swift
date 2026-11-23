import SwiftUI

private let navigationMargin: CGFloat = 20

// Home · Find · Shelf
// Keep navigation definitions in this file only.
enum MainTab: Int, CaseIterable {
    case home, find, shelf

    // Keep the existing lowercase asset keys and accessibility identifiers stable.
    var label: String {
        switch self {
        case .home: return "home"
        case .find: return "find"
        case .shelf: return "shelf"
        }
    }

    var displayLabel: String {
        switch self {
        case .home: return "Home"
        case .find: return "Find"
        case .shelf: return "Shelf"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: GuardianStore
    @State private var selected: MainTab = .home
    @State private var deletionCleanupMessage: String?
    @State private var recognitionGuardianID: UUID?
    @State private var recognitionRequestID = UUID()

    var body: some View {
        currentScreen
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(NavigationBarPlacement(selected: $selected))
            .onReceive(NotificationCenter.default.publisher(for: .guardianRecognitionRequested)) { notification in
                guard let source = notification.object as? GuardianStore, source === store,
                      let guardianID = notification.userInfo?["guardianID"] as? UUID,
                      store.guardian(guardianID) != nil else { return }
                recognitionGuardianID = guardianID
                recognitionRequestID = UUID()
                selected = .find
            }
            .onChange(of: selected) { _, tab in
                if tab != .find { recognitionGuardianID = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .guardianDeleted)) { notification in
                guard let source = notification.object as? GuardianStore, source === store else { return }
                selected = .shelf
                if let message = notification.userInfo?["cleanupMessage"] as? String {
                    // Let the profile dismiss before presenting a rare file-cleanup issue.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { deletionCleanupMessage = message }
                }
            }
            .alert("Guardian deleted", isPresented: Binding(
                get: { deletionCleanupMessage != nil },
                set: { if !$0 { deletionCleanupMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deletionCleanupMessage = nil }
            } message: {
                Text(deletionCleanupMessage ?? "")
            }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch selected {
        case .home:
            HomeView(goFind: { selected = .find })
        case .find:
            FindView(selectedGuardianID: recognitionGuardianID)
                .id(recognitionRequestID)
        case .shelf:
            ShelfView(goFind: { selected = .find })
        }
    }
}

extension Notification.Name {
    static let guardianRecognitionRequested = Notification.Name("ObjectGuardians.guardianRecognitionRequested")
    static let guardianDeleted = Notification.Name("ObjectGuardians.guardianDeleted")
}

/// Shares physical-screen-edge placement between the app and navigation previews.
private struct NavigationBarPlacement: ViewModifier {
    @Binding var selected: MainTab
    var reduceMotion: Bool? = nil
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            // Root geometry is stable when camera content ignores its own safe area.
            // Account for the SVG's existing two-pixel clear edge without measuring
            // the bar and feeding its resulting position back into layout state.
            let outlineInset = 2 / max(displayScale, 1)
            let bottomOffset = geometry.safeAreaInsets.bottom - OGLayout.standaloneBottomGap + outlineInset
            ZStack(alignment: .bottom) {
                content
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear
                            .frame(height: max(0, 74 + 8 - bottomOffset))
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(0)
                SketchBottomNavigation(selected: $selected, reduceMotionOverride: reduceMotion)
                    .padding(.horizontal, navigationMargin)
                    .offset(y: bottomOffset)
                    .background(Color.clear)
                    .zIndex(1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.ogBackground)
    }
}

/// Keeps the bar and touch targets fixed while the selected ink pill travels between tabs.
struct SketchBottomNavigation: View {
    @Binding var selected: MainTab
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private let inset: CGFloat = 10
    private let spacing: CGFloat = 6
    private let tabHeight: CGFloat = 54

    private var selectedArtwork: SVGPillArtwork {
        switch selected {
        case .home: return .navigationHome
        case .find: return .navigationFind
        case .shelf: return .navigationShelf
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let tabWidth = (geometry.size.width - 2 * inset - 2 * spacing) / 3

            ZStack(alignment: .topLeading) {
                SVGSketchPill(artwork: selectedArtwork)
                    .frame(width: tabWidth, height: tabHeight)
                    .phaseAnimator([1.0, 1.025, 1.0], trigger: selected) { pill, scale in
                        pill.scaleEffect(reduceMotion ? 1 : scale)
                    } animation: { _ in
                        reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.88)
                    }
                    .offset(x: inset + CGFloat(selected.rawValue) * (tabWidth + spacing), y: inset)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: selected)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack(spacing: spacing) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        NavigationTabButton(
                            tab: tab,
                            isSelected: selected == tab,
                            width: tabWidth,
                            reduceMotion: reduceMotion,
                            action: { selected = tab }
                        )
                    }
                }
                .padding(inset)
            }
            .background {
                SVGSketchPill(artwork: .navigationOuter)
            }
        }
        .frame(height: tabHeight + 2 * inset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottom-navigation")
    }
}

private struct NavigationTabButton: View {
    let tab: MainTab
    let isSelected: Bool
    let width: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SketchNavigationIcon(tab: tab, isSelected: isSelected, reduceMotion: reduceMotion)
                if isSelected {
                    Text(tab.displayLabel)
                        .font(OGType.font(20, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .transition(.opacity.animation(reduceMotion ? nil : .easeOut(duration: 0.16)))
                }
            }
            .foregroundColor(Color.ogInk)
            .padding(.horizontal, 8)
            .frame(width: width, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("nav-\(tab.label)")
    }
}

#Preview("Navigation · Home") {
    NavigationBarPreview(selected: .home)
}

#Preview("Navigation · Find") {
    NavigationBarPreview(selected: .find)
}

#Preview("Navigation · Shelf") {
    NavigationBarPreview(selected: .shelf)
}

#Preview("Navigation · Narrow / Larger Text") {
    NavigationBarPreview(selected: .home)
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Navigation · Reduce Motion") {
    NavigationBarPreview(selected: .find, reduceMotion: true)
}

private struct NavigationBarPreview: View {
    @State var selected: MainTab
    var reduceMotion: Bool? = nil

    var body: some View {
        Color.ogBackground
            .modifier(NavigationBarPlacement(selected: $selected, reduceMotion: reduceMotion))
    }
}
