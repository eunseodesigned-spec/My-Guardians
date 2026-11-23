import SwiftUI
import UIKit

/// Original paths extracted from the supplied Figma icon sheet as vector PDFs.
struct SketchNavigationIcon: View {
    let tab: MainTab
    var isSelected: Bool = false
    var reduceMotion: Bool = false

    var body: some View {
        #if DEBUG
        let _ = Self.verifiedArtwork
        #endif
        ZStack {
            icon("outline")
                .opacity(isSelected ? 0 : 1)
            icon("filled")
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
        .accessibilityHidden(true)
    }

    #if DEBUG
    private static let verifiedArtwork: Void = {
        for tab in MainTab.allCases {
            for variant in ["outline", "filled"] {
                let name = "nav-\(tab.label)-\(variant)"
                guard let image = UIImage(named: name) else {
                    preconditionFailure("Missing navigation artwork: \(name)")
                }
                precondition(image.size == CGSize(width: 24, height: 24), "Unexpected navigation artwork bounds: \(name)")
            }
        }
        print("[Navigation] Verified all 6 original vector icon assets at 24 pt")
    }()
    #endif

    private func icon(_ variant: String) -> some View {
        Image("nav-\(tab.label)-\(variant)")
            .renderingMode(tab == .shelf ? .original : .template)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color.ogInk)
    }
}

#Preview("Navigation Icon Artwork") {
    VStack(spacing: 24) {
        ForEach(MainTab.allCases, id: \.self) { tab in
            HStack(spacing: 32) {
                SketchNavigationIcon(tab: tab)
                SketchNavigationIcon(tab: tab, isSelected: true)
            }
        }
    }
    .padding(24)
    .background(Color.ogBackground)
}
