import SwiftUI
import UIKit

extension Color {
    static let ogInk = Color(red: 0, green: 0, blue: 0)
    /// Screen canvas, including safe areas and the space around components.
    static let ogBackground = Color(red: 245/255, green: 245/255, blue: 245/255)
    /// White component interiors; original SVG fills use this same #FFFFFF.
    static let ogPaper = Color.white
    static let ogButter = Color(red: 1, green: 252/255, blue: 132/255)
    static let ogBlue = Color(red: 184/255, green: 203/255, blue: 235/255)
    static let ogGreen = Color(red: 159/255, green: 174/255, blue: 105/255)
    static let ogPink = Color(red: 246/255, green: 186/255, blue: 220/255)
}

/// Shared screen rhythm; navigation keeps its established placement constants.
enum OGLayout {
    static let screenMargin: CGFloat = 24
    static let headerTop: CGFloat = 8
    static let headerHeight: CGFloat = 56
    static let controlGap: CGFloat = 4
    static let buttonPairGap: CGFloat = 12
    static let gap: CGFloat = 16
    static let sectionGap: CGFloat = 24
    static let actionTop: CGFloat = 8
    static let actionBottom: CGFloat = 16
    static let primaryNavigationGap: CGFloat = 18
    static let standaloneBottomGap: CGFloat = 24
    static let profileBottomGap = standaloneBottomGap
    static let primaryMinimumHeight: CGFloat = 48
    static let minimumCanvasHeight: CGFloat = 240
    static let creationCanvasHeight: CGFloat = 466
    static let supportingCopyHeight: CGFloat = 160
    static let namingFieldsHeight: CGFloat = 216
    static let memoryMetadataHeight: CGFloat = 288
    static let profileArtworkSize: CGFloat = 180
}

extension View {
    func ogScreenHeader() -> some View {
        padding(.horizontal, OGLayout.screenMargin)
            .padding(.top, OGLayout.headerTop)
    }

    func ogBottomAction(aboveNavigationBar: Bool = false, respectsKeyboard: Bool = true) -> some View {
        modifier(FixedPrimaryActionPlacement(aboveNavigationBar: aboveNavigationBar, respectsKeyboard: respectsKeyboard))
    }

    /// Draw beneath fixed controls, but let the final content scroll completely above them.
    func ogScrollBehindBottomControls(minimumBottomClearance: CGFloat = 0) -> some View {
        modifier(BottomControlScrollClearance(minimumBottomClearance: minimumBottomClearance))
    }
}

private struct FixedPrimaryActionPlacement: ViewModifier {
    let aboveNavigationBar: Bool
    let respectsKeyboard: Bool
    @State private var bottomPadding = OGLayout.actionBottom

    func body(content: Content) -> some View {
        let currentPadding = bottomPadding
        content
            .offset(y: aboveNavigationBar ? OGLayout.actionBottom + OGLayout.actionTop - OGLayout.primaryNavigationGap : 0)
            .background {
                if !aboveNavigationBar {
                    WindowBottomEdgeAnchor(respectsKeyboard: respectsKeyboard) { correction in
                        let padding = currentPadding - correction
                        guard abs(padding - bottomPadding) > 0.1 else { return }
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { bottomPadding = padding }
                    }
                    .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, OGLayout.screenMargin)
            .padding(.top, OGLayout.actionTop)
            .padding(.bottom, aboveNavigationBar ? OGLayout.actionBottom : bottomPadding)
            .background(Color.clear)
    }
}

private struct BottomScrollBounds: Equatable {
    var viewportBottom: CGFloat?
    var expandedBottom: CGFloat?
    var scale: CGFloat = 1
}

private struct BottomScrollBoundsKey: PreferenceKey {
    static let defaultValue = BottomScrollBounds()

    static func reduce(value: inout BottomScrollBounds, nextValue: () -> BottomScrollBounds) {
        let next = nextValue()
        if let bottom = next.viewportBottom { value.viewportBottom = bottom }
        if let bottom = next.expandedBottom {
            value.expandedBottom = bottom
            value.scale = next.scale
        }
    }
}

private struct BottomControlScrollClearance: ViewModifier {
    let minimumBottomClearance: CGFloat
    @State private var measuredClearance: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear.preference(key: BottomScrollBoundsKey.self, value: BottomScrollBounds(
                        expandedBottom: frame.maxY,
                        scale: frame.height / max(geometry.size.height, 1)
                    ))
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: BottomScrollBoundsKey.self, value: BottomScrollBounds(
                        viewportBottom: geometry.frame(in: .global).maxY
                    ))
                }
                .allowsHitTesting(false)
            }
            .contentMargins(.bottom, max(measuredClearance, minimumBottomClearance), for: .scrollContent)
            .onPreferenceChange(BottomScrollBoundsKey.self) { bounds in
                guard let expanded = bounds.expandedBottom, let viewport = bounds.viewportBottom else { return }
                let clearance = max(0, (expanded - viewport) / max(bounds.scale, 0.001))
                if abs(clearance - measuredClearance) > 0.1 { measuredClearance = clearance }
            }
    }
}

enum OGType {
    static let fontName = "PatrickHand-Regular"

    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(fontName, size: size, relativeTo: style)
    }

    /// Use the same face when drawing text into UIKit images.
    static func uiFont(_ size: CGFloat) -> UIFont {
        guard let font = UIFont(name: fontName, size: size), font.fontName == fontName else {
            preconditionFailure("Patrick Hand is unavailable. Check UIAppFonts and Copy Bundle Resources.")
        }
        return font
    }

    #if DEBUG
    /// Check automatic Info.plist registration; do not manually register a missing resource.
    static func verifyFontRegistration() {
        let registeredFonts = Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String] ?? []
        precondition(registeredFonts.contains("PatrickHand-Regular.ttf"), "Patrick Hand is missing from UIAppFonts.")
        precondition(Bundle.main.url(forResource: fontName, withExtension: "ttf") != nil, "Patrick Hand is missing from the app bundle.")
        let resolvedFont = uiFont(21)
        print("[OGType] Verified bundled font: \(resolvedFont.fontName); family: \(resolvedFont.familyName)")
    }
    #endif

    static let title = font(32, relativeTo: .title)
    static let section = font(24, relativeTo: .title2)
    static let body = font(18)
    static let button = font(18, relativeTo: .headline)
    static let caption = font(14, relativeTo: .caption)
}

/// Shared procedural ink for fields, cards, and camera controls.
enum SketchInk {
    static let lineWidth: CGFloat = 2
    static let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

    // These match the reference's restrained frequency, wiggle, and smoothing.
    static let frequency: CGFloat = 1.3
    static let wiggle: CGFloat = 0.15
    static let smoothing: CGFloat = 0.5

    fileprivate static let wavelength: CGFloat = 22 / frequency
    fileprivate static let displacement: CGFloat = 5 * wiggle
}

/// Shared treatment for text displayed over the live camera.
struct CameraTextLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .background(SketchOutline(radius: 12).fill(Color.white))
            .overlay(SketchOutline(radius: 12).stroke(Color.black, style: SketchInk.strokeStyle))
    }
}

/// A rounded sketch outline for controls without supplied SVG artwork.
struct SketchOutline: Shape {
    var radius: CGFloat = 15

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        SketchInkPath.path(in: rect, radius: radius, inset: CGSize(width: 1.2, height: 1.5))
    }
}

/// Fully rounded at every aspect ratio, with deterministic hand-drawn edges.
struct SketchCapsule: Shape {
    func path(in rect: CGRect) -> Path {
        SketchInkPath.path(in: rect, radius: min(rect.width, rect.height) / 2,
                           inset: CGSize(width: 1.25, height: 1.25))
    }
}

/// Original SVG fill and expanded ink paths, preserved as vector PDF assets.
/// Corner pieces stay at their native size; only the middle fragments resize.
enum SVGPillArtwork: String {
    case primary = "svg-primary-pill"
    case navigationOuter = "svg-nav-outer"
    case navigationHome = "svg-nav-selected-home"
    case navigationFind = "svg-nav-selected-find"
    case navigationShelf = "svg-nav-selected-shelf"

    fileprivate var capInset: CGFloat {
        switch self {
        case .primary: return 23
        case .navigationOuter: return 32
        case .navigationHome, .navigationFind, .navigationShelf: return 26
        }
    }
}

struct SVGSketchPill: View {
    let artwork: SVGPillArtwork
    var isTallButton: Bool = false

    var body: some View {
        let inset = isTallButton && artwork == .primary ? 24 : artwork.capInset
        Image(artwork.rawValue)
            .renderingMode(.original)
            .resizable(capInsets: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset),
                       resizingMode: .stretch)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private enum SketchInkPath {
    private struct Sample {
        var point: CGPoint
        var tangent: CGVector
    }

    static func path(in rect: CGRect, radius requestedRadius: CGFloat, inset: CGSize) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width > 0, rect.height > 0 else { return Path() }
        let bounds = rect.insetBy(dx: min(inset.width, rect.width / 4),
                                  dy: min(inset.height, rect.height / 4))
        let radius = requestedRadius.isFinite
            ? max(0, min(requestedRadius, bounds.width / 2, bounds.height / 2)) : 0
        let amplitude = min(SketchInk.displacement, min(bounds.width, bounds.height) * 0.03)
        let left = bounds.minX, right = bounds.maxX
        let top = bounds.minY, bottom = bounds.maxY
        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))

        edge(&path, from: CGPoint(x: left + radius, y: top),
             to: CGPoint(x: right - radius, y: top), phase: 0.37, amplitude: amplitude)
        corner(&path, center: CGPoint(x: right - radius, y: top + radius), radius: radius,
               startAngle: -.pi / 2, phase: 1.1, amplitude: amplitude)
        edge(&path, from: CGPoint(x: right, y: top + radius),
             to: CGPoint(x: right, y: bottom - radius), phase: 2.11, amplitude: amplitude)
        corner(&path, center: CGPoint(x: right - radius, y: bottom - radius), radius: radius,
               startAngle: 0, phase: 2.3, amplitude: amplitude)
        edge(&path, from: CGPoint(x: right - radius, y: bottom),
             to: CGPoint(x: left + radius, y: bottom), phase: 4.3, amplitude: amplitude)
        corner(&path, center: CGPoint(x: left + radius, y: bottom - radius), radius: radius,
               startAngle: .pi / 2, phase: 3.7, amplitude: amplitude)
        edge(&path, from: CGPoint(x: left, y: bottom - radius),
             to: CGPoint(x: left, y: top + radius), phase: 1.6, amplitude: amplitude)
        corner(&path, center: CGPoint(x: left + radius, y: top + radius), radius: radius,
               startAngle: .pi, phase: 5.2, amplitude: amplitude)
        path.closeSubpath()
        return path
    }

    private static func edge(_ path: inout Path, from start: CGPoint, to end: CGPoint,
                             phase: CGFloat, amplitude: CGFloat) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        // At a circular capsule, the straight segments shrink to a point.
        guard length > 0.00000001 else { return }
        let direction = CGVector(dx: dx / length, dy: dy / length)
        let normal = CGVector(dx: direction.dy, dy: -direction.dx)
        let fadeLength = min(12, length / 2)
        let amount = amplitude * min(1, length / 24)
        let waveNumber = 2 * CGFloat.pi / SketchInk.wavelength
        let secondary = 0.32 * (1 - SketchInk.smoothing)

        // Coordinates are measured in points, so a wider field adds waves rather
        // than stretching the same squiggle. Both endpoint derivatives vanish.
        append(&path, length: length, segments: 64) { distance in
            let a = smoothstep(distance / fadeLength)
            let b = smoothstep((length - distance) / fadeLength)
            let envelope = a.value * b.value
            let envelopeSlope = (a.slope * b.value - a.value * b.slope) / fadeLength
            let first = waveNumber * distance + phase
            let second = waveNumber * distance / 1.73 + phase * 1.9
            let wave = (1 - secondary) * sin(first) + secondary * sin(second)
            let waveSlope = waveNumber * ((1 - secondary) * cos(first) + secondary * cos(second) / 1.73)
            // A small inward bias keeps the ink inside the existing layout box.
            let drift = -amount * envelope * (0.5 + 0.5 * wave)
            let slope = -amount * (envelopeSlope * (0.5 + 0.5 * wave) + envelope * 0.5 * waveSlope)
            return Sample(point: CGPoint(x: start.x + direction.dx * distance + normal.dx * drift,
                                         y: start.y + direction.dy * distance + normal.dy * drift),
                          tangent: CGVector(dx: direction.dx + normal.dx * slope,
                                            dy: direction.dy + normal.dy * slope))
        }
    }

    private static func corner(_ path: inout Path, center: CGPoint, radius: CGFloat,
                               startAngle: CGFloat, phase: CGFloat, amplitude: CGFloat) {
        guard radius > 0 else { return }
        let amount = min(amplitude * 0.18, radius * 0.03)
        append(&path, length: .pi / 2, segments: 8) { angle in
            let theta = startAngle + angle
            let sine = sin(2 * angle), cosine = cos(2 * angle)
            let wave = 2.7 * angle + phase
            let drift = -amount * sine * sine * (0.5 + 0.5 * sin(wave))
            let slope = -amount * (4 * sine * cosine * (0.5 + 0.5 * sin(wave)) +
                                   sine * sine * 1.35 * cos(wave))
            let x = cos(theta), y = sin(theta)
            return Sample(point: CGPoint(x: center.x + (radius + drift) * x,
                                         y: center.y + (radius + drift) * y),
                          tangent: CGVector(dx: slope * x - (radius + drift) * y,
                                            dy: slope * y + (radius + drift) * x))
        }
    }

    /// Quintic easing keeps the edge drift and its slope flat at each corner.
    private static func smoothstep(_ value: CGFloat) -> (value: CGFloat, slope: CGFloat) {
        let t = min(1, max(0, value))
        return (t * t * t * (t * (t * 6 - 15) + 10), 30 * t * t * (t - 1) * (t - 1))
    }

    /// Cubic Hermite interpolation follows the analytic point and tangent. The
    /// fixed sample count avoids changing the wave geometry during animations.
    private static func append(_ path: inout Path, length: CGFloat, segments: Int,
                               sample: (CGFloat) -> Sample) {
        let step = length / CGFloat(segments)
        var previous = sample(0)
        for index in 1...segments {
            let next = sample(CGFloat(index) * step)
            path.addCurve(to: next.point,
                          control1: CGPoint(x: previous.point.x + previous.tangent.dx * step / 3,
                                            y: previous.point.y + previous.tangent.dy * step / 3),
                          control2: CGPoint(x: next.point.x - next.tangent.dx * step / 3,
                                            y: next.point.y - next.tangent.dy * step / 3))
            previous = next
        }
    }
}

struct SketchButton: View {
    enum IllustrationPlacement { case leading, trailing }
    var label: String
    var prominent: Bool = false
    var action: () -> Void
    var illustration: String? = nil
    var cardSize: CGSize? = nil
    var cardIllustrationSize: CGFloat? = nil
    var illustrationPlacement: IllustrationPlacement = .leading
    var buttonSize: CGSize? = nil
    var cornerRadius: CGFloat? = nil
    var labelVerticalPadding: CGFloat? = nil

    init(label: String, prominent: Bool = false, illustration: String? = nil,
         cardSize: CGSize? = nil, cardIllustrationSize: CGFloat? = nil, illustrationPlacement: IllustrationPlacement = .leading,
         buttonSize: CGSize? = nil, cornerRadius: CGFloat? = nil, labelVerticalPadding: CGFloat? = nil,
         action: @escaping () -> Void) {
        self.label = label
        self.prominent = prominent
        self.action = action
        self.illustration = illustration
        self.cardSize = cardSize
        self.cardIllustrationSize = cardIllustrationSize
        self.illustrationPlacement = illustrationPlacement
        self.buttonSize = buttonSize
        self.cornerRadius = cornerRadius
        self.labelVerticalPadding = labelVerticalPadding
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let buttonSize {
                    buttonText.frame(width: buttonSize.width, height: buttonSize.height)
                } else if let labelVerticalPadding {
                    buttonText
                        .padding(.vertical, labelVerticalPadding)
                        .frame(maxWidth: .infinity)
                } else if let cardSize {
                    VStack(spacing: 24) {
                        if let illustration {
                            artwork(illustration, size: cardIllustrationSize ?? (prominent ? 16 : 40), originalAsset: cardIllustrationSize != nil)
                        }
                        buttonText
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .frame(width: cardSize.width)
                    .frame(minHeight: cardSize.height)
                } else {
                    HStack(spacing: 8) {
                        if let illustration, illustrationPlacement == .leading {
                            artwork(illustration, size: prominent ? 16 : 24)
                        }
                        buttonText
                        if let illustration, illustrationPlacement == .trailing {
                            artwork(illustration, size: prominent ? 16 : 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: OGLayout.primaryMinimumHeight)
                }
            }
            .foregroundColor(Color.ogInk)
            .background {
                if let cornerRadius {
                    SketchOutline(radius: cornerRadius).fill(prominent ? Color.ogButter : Color.ogPaper)
                } else if prominent {
                    SVGSketchPill(artwork: .primary, isTallButton: cardSize != nil)
                } else {
                    SketchOutline(radius: cardSize == nil ? 24 : 16).fill(Color.ogPaper)
                }
            }
            .overlay {
                if let cornerRadius {
                    SketchOutline(radius: cornerRadius)
                        .stroke(Color.ogInk, style: SketchInk.strokeStyle)
                } else if !prominent {
                    SketchOutline(radius: cardSize == nil ? 24 : 16)
                        .stroke(Color.ogInk, style: SketchInk.strokeStyle)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var buttonText: some View {
        Text(label)
            .font(OGType.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func artwork(_ name: String, size: CGFloat, originalAsset: Bool = false) -> some View {
        Image(prominent && !originalAsset ? "button-\(name)" : name)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SketchCard<Content: View>: View {
    let content: Content
    var fill: Color = .ogPaper
    var contentInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    var body: some View {
        content
            .font(OGType.body)
            .foregroundColor(Color.ogInk)
            .padding(contentInsets)
            .background(SketchOutline(radius: 16).fill(fill))
            .overlay(SketchOutline(radius: 16).stroke(Color.ogInk, style: SketchInk.strokeStyle))
    }
}

struct SketchField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(OGType.body)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color.ogInk.opacity(0.6)))
                .font(OGType.body)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.words)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { isFocused = false }
                .tint(Color.ogInk)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .frame(minHeight: 48)
                .background(SketchOutline(radius: 12).fill(Color.ogPaper))
                .overlay(SketchOutline(radius: 12).stroke(Color.ogInk, style: SketchInk.strokeStyle))
                .accessibilityLabel(label)
        }
        .foregroundColor(Color.ogInk)
    }
}

struct SketchHeader: View {
    enum TitleAlignment {
        case leading, center
    }

    let title: String
    var closeTitle: String = "Back"
    var onBack: (() -> Void)?
    var titleAlignment: TitleAlignment = .center
    var trailingAsset: String? = nil
    var trailingIconAlignment: Alignment = .center
    var trailingAction: (() -> Void)? = nil
    var trailingAccessibilityLabel: String = "More options"
    var titleAccessibilityIdentifier: String? = nil
    var titleFont: Font? = nil

    var body: some View {
        HStack(spacing: 8) {
            if titleAlignment == .center {
                if onBack != nil {
                    backButton
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            } else if onBack != nil {
                backButton
            }

            Text(title)
                .font(titleFont ?? OGType.title)
                .accessibilityIdentifier(titleAccessibilityIdentifier ?? title)
                .multilineTextAlignment(titleAlignment == .leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: titleAlignment == .leading ? .leading : .center)

            if let trailingAsset, let trailingAction {
                Button(action: trailingAction) {
                    Image(trailingAsset)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44, alignment: trailingIconAlignment)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trailingAccessibilityLabel)
            } else if titleAlignment == .center {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(minHeight: OGLayout.headerHeight)
        .foregroundColor(Color.ogInk)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button(action: onBack) {
                Image("screen-back")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeTitle)
        }
    }
}

struct GuardianArtwork: View {
    let filename: String
    var trimTransparentMargins = false
    var body: some View {
        ArtworkLoader(filename: filename, trimTransparentMargins: trimTransparentMargins)
    }
}

/// Removes only transparent canvas margins for collection thumbnails; never edits saved files.
private enum GuardianThumbnailCrop {
    static let cache = NSCache<NSString, UIImage>()

    static func image(_ image: UIImage, key: String) -> UIImage {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let source = image.cgImage else { return image }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                let data = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where data[(y * width + x) * 4 + 3] > 0 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        let result = bounds.flatMap { source.cropping(to: $0) }.map {
            UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation)
        } ?? image
        cache.setObject(result, forKey: key as NSString)
        return result
    }
}

/// Uses the shared Documents directory (the catalog holds only filenames).
private struct ArtworkLoader: View {
    @EnvironmentObject private var store: GuardianStore
    let filename: String
    var trimTransparentMargins = false
    var body: some View {
        Group {
            if let ui = store.image(filename) {
                Image(uiImage: trimTransparentMargins
                      ? GuardianThumbnailCrop.image(ui, key: "\(ObjectIdentifier(store))-\(filename)") : ui)
                    .resizable().scaledToFit()
            } else {
                Image(systemName: "scribble.variable").resizable().scaledToFit().padding(20)
            }
        }
        .accessibilityLabel("Hand-drawn guardian")
    }
}

#Preview("Button Components") {
    VStack(spacing: 16) {
        SketchButton(
            label: "Create guardian",
            prominent: true,
            action: {}
        )

        SketchButton(
            label: "Take photo",
            prominent: false,
            action: {}
        )
    }
    .padding(24)
    .background(Color.ogBackground)
}

#Preview("Original SVG Pill Widths") {
    VStack(spacing: 24) {
        ForEach([CGFloat(362), CGFloat(280)], id: \.self) { width in
            ZStack(alignment: .leading) {
                SVGSketchPill(artwork: .navigationOuter)

                SVGSketchPill(artwork: .navigationHome)
                    .frame(width: 110, height: 54)
                    .padding(.leading, 10)
            }
            .frame(width: width, height: 74)
        }
    }
    .padding(12)
    .background(Color.ogBackground)
}

#Preview("Card Components") {
    SketchCard(content: VStack(alignment: .leading, spacing: 8) {
        Text("Momo").font(OGType.title)
        Text("A little guardian for your favorite mug.")
        Text("Made with a little everyday magic.").font(OGType.caption)
    })
    .padding(24)
    .background(Color.ogBackground)
}

#Preview("Organic edges · Short and tall") {
    VStack(spacing: 24) {
        SketchButton(label: "A longer primary button\nkeeps its capsule ends", prominent: true, action: {})
        HStack(alignment: .top, spacing: 16) {
            SketchOutline(radius: 16)
                .stroke(Color.ogInk, style: SketchInk.strokeStyle)
                .frame(width: 140, height: 196)
            SketchOutline(radius: 22)
                .stroke(Color.ogInk, style: SketchInk.strokeStyle)
                .frame(width: 164, height: 280)
        }
    }
    .padding(24)
    .background(Color.ogBackground)
}

#Preview("Illustrated Button") {
    SketchButton(
        label: "Find my first\nhome guardian",
        prominent: true,
        illustration: "home-find",
        cardSize: CGSize(width: 164, height: 196),
        action: {}
    )
    .padding(24)
    .background(Color.ogBackground)
}

#Preview("Headers") {
    VStack(spacing: 24) {
        SketchHeader(title: "Anybody home?", titleAlignment: .leading,
                     trailingAsset: "home-settings", trailingAction: {},
                     trailingAccessibilityLabel: "Settings")
        SketchHeader(title: "Draw guardian", onBack: {})
    }
    .padding(24)
    .background(Color.ogBackground)
}

#Preview("Input Fields") {
    SketchFieldsPreview()
        .padding(24)
        .background(Color.ogBackground)
}

#Preview("Typography") {
    VStack(alignment: .leading, spacing: 12) {
        Text("A little everyday magic").font(OGType.title)
        Text("Little memories").font(OGType.section)
        Text("Give your favorite objects a friend.").font(OGType.body)
        Text("Create guardian").font(OGType.button)
        Text("Every guardian starts with a sketch.").font(OGType.caption)
    }
    .foregroundColor(Color.ogInk)
    .padding(24)
    .background(Color.ogBackground)
}

#Preview("Larger Text") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            SketchCard(content: VStack(alignment: .leading, spacing: 8) {
                Text("Room to grow").font(OGType.title)
                Text("Cards and controls make space for larger text.")
            })
            SketchFieldsPreview()
            SketchButton(label: "Find my first guardian", prominent: true, action: {})
            SketchButton(label: "Keep exploring", action: {})
        }
        .padding(24)
    }
    .background(Color.ogBackground)
    .environment(\.dynamicTypeSize, .accessibility3)
}

private struct SketchFieldsPreview: View {
    @State private var guardianName = ""
    @State private var objectName = "My favorite mug"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SketchField(label: "Guardian name", text: $guardianName, placeholder: "e.g. Momo")
            SketchField(label: "Object name (optional)", text: $objectName, placeholder: "e.g. My favorite mug")
        }
    }
}

// A native sheet can retain its own safe-area inset and presentation scale.
// Measure an unshifted overlay sibling in window coordinates, independently of scrolling.
struct WindowBottomEdgeAnchor: UIViewRepresentable {
    var respectsKeyboard = false
    let onOffset: (CGFloat) -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onOffset = onOffset
        view.respectsKeyboard = respectsKeyboard
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.onOffset = onOffset
        view.respectsKeyboard = respectsKeyboard
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: ()) {
        view.onOffset = nil
        view.stopObservingKeyboard()
    }

    final class AnchorView: UIView {
        var onOffset: ((CGFloat) -> Void)?
        var respectsKeyboard = false
        private var keyboardFrame: CGRect?
        private var keyboardObserver: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, respectsKeyboard, keyboardObserver == nil {
                keyboardObserver = NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
                ) { [weak self] notification in
                    let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                    DispatchQueue.main.async {
                        self?.keyboardFrame = frame
                        self?.measure()
                    }
                }
            } else if window == nil {
                stopObservingKeyboard()
            }
            DispatchQueue.main.async { [weak self] in self?.measure() }
            // Recheck once the sheet's entrance animation reaches its final transform.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in self?.measure() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        func stopObservingKeyboard() {
            if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
            keyboardObserver = nil
        }

        private func measure() {
            guard let window, bounds.height > 0 else { return }
            let frame = convert(bounds, to: window)
            let scale = frame.height / bounds.height
            guard scale > 0 else { return }
            // Preserve the SVG unchanged while accounting for its two-pixel clear lower edge.
            let outlineInset = 2 / max(window.traitCollection.displayScale, 1)
            var bottomEdge = window.bounds.maxY
            if respectsKeyboard, let keyboardFrame {
                let screen = window.windowScene?.screen ?? window.screen
                let keyboard = window.convert(keyboardFrame, from: screen.coordinateSpace)
                if keyboard.width >= window.bounds.width * 0.8, keyboard.intersects(window.bounds) {
                    bottomEdge = min(bottomEdge, keyboard.minY)
                }
            }
            onOffset?((bottomEdge - frame.maxY - OGLayout.standaloneBottomGap + outlineInset) / scale)
        }
    }
}
