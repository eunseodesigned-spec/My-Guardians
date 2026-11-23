import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var store: GuardianStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var selectedGuardian: Guardian?
    @State private var wandering = HomeWandering(
        artworkSize: CGSize(width: 77, height: 95),
        // Canonical motion coordinates retain the roof and leave the hint unobstructed.
        housePolygon: [
            CGPoint(x: 16, y: 530), CGPoint(x: 16, y: 152),
            CGPoint(x: 199.8, y: 16), CGPoint(x: 380, y: 152),
            CGPoint(x: 378, y: 530)
        ]
    )
    var goFind: () -> Void

    private var isEmpty: Bool { store.guardians.isEmpty }
    private var guardianIDs: [UUID] { store.guardians.map(\.id) }
    private static let houseArtworkSize = CGSize(width: 369, height: 605)

    var body: some View {
        #if DEBUG
        let _ = Self.verifiedHouseArtwork
        #endif
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { homeContent }
                .ogScrollBehindBottomControls()
            } else {
                homeContent
            }
        }
        .background(Color.ogBackground)
        .foregroundStyle(Color.ogInk)
        .guardianProfileSheet(selection: $selectedGuardian)
    }

    private var homeContent: some View {
        VStack(spacing: 8) {
            SketchHeader(
                title: isEmpty ? "Anybody home?" : "Everyone's home!",
                titleAlignment: .leading,
                trailingAsset: "home-settings",
                trailingIconAlignment: .trailing,
                trailingAction: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                },
                trailingAccessibilityLabel: "Open app settings",
                titleAccessibilityIdentifier: "home-title"
            )
            .ogScreenHeader()

            GeometryReader { geometry in
                house(in: geometry.size)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 600 : 0,
                   maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
        }
    }

    private func house(in available: CGSize) -> some View {
        let canvas = Self.houseArtworkSize
        let scale = max(0, min(available.width / canvas.width, available.height / canvas.height))
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let motionScaleX = size.width / HomeWandering.canvasSize.width
        let motionScaleY = size.height / HomeWandering.canvasSize.height

        return ZStack {
            Image("home-redesign-house")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)

            if isEmpty {
                SketchButton(
                    label: "Find my first\nhome guardian",
                    prominent: true,
                    illustration: "home-find-illustration",
                    cardSize: CGSize(width: min(164, size.width * 0.58), height: 196),
                    cardIllustrationSize: 56,
                    action: goFind
                )
                    .position(x: size.width / 2, y: size.height * 0.60)
                    .accessibilityLabel("Find my first home guardian")
                    .accessibilityIdentifier("home-first-guardian")
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: reduceMotion || scenePhase != .active)) { tick in
                    ZStack {
                        ForEach(store.guardians) { guardian in
                            if let point = wandering.position(for: guardian.id) {
                                Button { selectedGuardian = guardian } label: {
                                    // drawingFile is the saved combined object cutout + drawing.
                                    GuardianArtwork(filename: guardian.drawingFile, trimTransparentMargins: true)
                                        .frame(width: 60, height: 60)
                                }
                                .buttonStyle(.plain)
                                .position(x: point.x * motionScaleX, y: point.y * motionScaleY)
                                .accessibilityLabel("\(guardian.name), view profile")
                                .accessibilityIdentifier("home-guardian-\(guardian.id.uuidString)")
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .onChange(of: tick.date) { _, date in
                        wandering.update(ids: guardianIDs, at: date.timeIntervalSinceReferenceDate)
                    }
                }
                HStack(spacing: 8) {
                    Image("home-hand")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 28)
                        .accessibilityHidden(true)
                    Text("Tap a friend to say hello")
                        .font(OGType.font(20, relativeTo: .subheadline))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(width: size.width * 0.90)
                .position(x: size.width / 2 - 12, y: size.height * 0.935)
                .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Guardian home")
        .accessibilityIdentifier("home-house")
        .position(x: available.width / 2, y: available.height / 2)
        .onAppear {
            wandering.update(ids: guardianIDs, at: Date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: guardianIDs) { _, ids in
            wandering.update(ids: ids, at: Date.timeIntervalSinceReferenceDate)
        }
    }

    #if DEBUG
    private static let verifiedHouseArtwork: Void = {
        guard let image = UIImage(named: "home-redesign-house") else {
            preconditionFailure("The original Home.svg vector asset is missing from the app bundle.")
        }
        precondition(image.size == houseArtworkSize, "The updated Home.svg aspect ratio must be preserved.")
        print("[Home] Verified updated Home.svg vector artwork at 369 × 605 pt")
    }()
    #endif
}

#if DEBUG
#Preview("Empty Home") {
    HomeScreenPreview(occupied: false)
}

#Preview("Occupied Home") {
    HomeScreenPreview(occupied: true)
}

#Preview("Empty Home · Larger text") {
    HomeScreenPreview(occupied: false)
        .environment(\.dynamicTypeSize, .accessibility3)
}

private struct HomeScreenPreview: View {
    @StateObject private var store: GuardianStore

    init(occupied: Bool) {
        _store = StateObject(wrappedValue: HomePreviewFixtures.makeStore(occupied: occupied))
    }

    var body: some View {
        RootView()
            .environmentObject(store)
            .font(OGType.body)
            .preferredColorScheme(.light)
    }
}
#endif
