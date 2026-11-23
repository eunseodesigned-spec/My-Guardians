import SwiftUI
import PencilKit
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText

private enum BrushColor: String, CaseIterable, Identifiable {
    case blue, green, pink
    var id: String { rawValue }
    var color: UIColor {
        switch self {
        case .blue: return UIColor(red: 10/255, green: 88/255, blue: 218/255, alpha: 1)
        case .green: return UIColor(red: 131/255, green: 168/255, blue: 0, alpha: 1)
        case .pink: return UIColor(red: 242/255, green: 0, blue: 137/255, alpha: 1)
        }
    }
}

private struct DrawingPad: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var brush: UIColor
    var isEraser: Bool
    var undoSignal: Int
    var clearSignal: Int

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingPad
        var lastUndo = 0
        var lastClear = 0
        init(_ parent: DrawingPad) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let next = canvasView.drawing
            DispatchQueue.main.async { self.parent.drawing = next }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput
        view.isScrollEnabled = false
        view.delegate = context.coordinator
        view.drawing = drawing
        view.tool = PKInkingTool(.pen, color: brush, width: 6)
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        view.tool = isEraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: brush, width: 6)
        if clearSignal != context.coordinator.lastClear {
            context.coordinator.lastClear = clearSignal
            view.drawing = PKDrawing()
        }
        if undoSignal != context.coordinator.lastUndo {
            context.coordinator.lastUndo = undoSignal
            view.undoManager?.undo()
        }
    }
}

struct CreateGuardianFlow: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GuardianStore
    let referenceImage: UIImage
    var onFindAgain: (() -> Void)? = nil

    @State private var step = 0
    @State private var drawing = PKDrawing()
    @State private var ink: BrushColor = .blue
    @State private var erasing = false
    @State private var undoCounter = 0
    @State private var clearCounter = 0
    @State private var guardianName = ""
    @State private var objectName = ""
    @State private var preview: UIImage?        // Object cutout + guardian ink
    @State private var inkPreview: UIImage?     // Guardian ink only, for AR
    @State private var canvasSize = CGSize(width: 340, height: 390)
    @State private var created: Guardian?
    @State private var errorText: String?
    @State private var isolatedObject: UIImage?
    @State private var isRemovingBackground = false
    @State private var removalMessage: String?
    @State private var useOriginalImage = false
    @State private var showInfo = false
    private var isPreview = false
    private let namingCanvasHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: OGLayout.gap) {
            SketchHeader(
                title: step == 3 ? "All settled in!" : "Bring it to life",
                closeTitle: "Back", onBack: { if step == 0 || step == 3 { dismiss() } else { setStep(step - 1) } },
                trailingAsset: "screen-close", trailingAction: { showInfo = true },
                trailingAccessibilityLabel: "About creating a guardian", titleFont: OGType.section
            )
            .ogScreenHeader()
            GeometryReader { geometry in
                let canvasHeight = min(OGLayout.creationCanvasHeight,
                                       max(OGLayout.minimumCanvasHeight, geometry.size.height - OGLayout.supportingCopyHeight))
                if step == 0 { prepareStep(canvasHeight: canvasHeight) }
                if step == 1 { drawingStep(canvasHeight: canvasHeight) }
                if step == 2 { saveStep }
                if step == 3 { finishedStep(canvasHeight: canvasHeight) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                switch step {
                case 0: prepareAction
                case 1: nextAction
                case 2: saveAction
                default: finishedActions
                }
            }
            .ogBottomAction(respectsKeyboard: step != 2)
            .ignoresSafeArea(step == 2 ? .keyboard : [], edges: .bottom)
        }
        .background(Color.ogBackground)
        .presentationBackground(Color.ogBackground)
        .foregroundColor(.black)
        .task { if !isPreview { await prepareObjectCutout() } }
        .confirmationDialog("Information", isPresented: $showInfo, titleVisibility: .visible) {
            if step == 0 && !isRemovingBackground {
                if removalMessage != nil || useOriginalImage {
                    Button("Try background removal again") {
                        Task { await prepareObjectCutout(force: true) }
                    }
                    .accessibilityIdentifier("create-retry-removal")
                }
                if isolatedObject == nil && !useOriginalImage {
                    Button("Use original photo instead") { useOriginalImage = true }
                        .accessibilityIdentifier("create-use-original")
                }
            }
            Button("Got it") { showInfo = false }
        } message: {
            Text(informationMessage)
        }
        .onAppear { showInfo = false }
        .onDisappear { showInfo = false }
        .onChange(of: step) { showInfo = false }
        .alert(
            "Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
        ) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func setStep(_ nextStep: Int) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = nextStep
        }
    }

    // The original camera photo remains untouched for later recognition.
    // The object cutout and ink are composed together for the saved artwork.
    private func prepareStep(canvasHeight: CGFloat) -> some View {
            ScrollView {
                VStack(spacing: OGLayout.sectionGap) {
                    ZStack {
                        SketchOutline(radius: 16).fill(Color.ogPaper)
                        if let image = isolatedObject ?? (useOriginalImage ? referenceImage : nil) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        } else if isRemovingBackground {
                            VStack(spacing: 14) {
                                ProgressView()
                                Text("Removing the background...")
                                    .font(OGType.font(19))
                            }
                        } else {
                            Image(uiImage: referenceImage)
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        }
                    }
                    .frame(height: canvasHeight)
                    .overlay(SketchOutline(radius: 16).stroke(Color.ogInk, style: SketchInk.strokeStyle))
                    .padding(.horizontal, OGLayout.screenMargin)

                    Text("This object has a little guardian!")
                        .font(OGType.section)
                        .multilineTextAlignment(.center)

                    if removalMessage == nil || useOriginalImage {
                        Text("Your object's ready. Now bring its\nguardian to life with a drawing.")
                            .font(OGType.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, OGLayout.gap)
            }
            .ogScrollBehindBottomControls()
    }

    private var informationMessage: String {
        var message =
            "Draw on your isolated object, then give its guardian a name. Your object and drawing are saved together; a separate ink layer is used for camera memories."
        if step == 0, let removalMessage, !useOriginalImage {
            message += "\n\n\(removalMessage)"
        }
        if useOriginalImage {
            message += "\n\nUsing your original photo."
        }
        return message
    }

    @MainActor
    private func prepareObjectCutout(force: Bool = false) async {
        guard force || (isolatedObject == nil && removalMessage == nil && !isRemovingBackground) else {
            return
        }
        isRemovingBackground = true
        removalMessage = nil
        useOriginalImage = false
        do {
            isolatedObject = try await ForegroundCutout.create(from: referenceImage)
        } catch {
            removalMessage =
                "Couldn't separate the object. Try a clearer photo with one object in front, or continue with the original image."
        }
        isRemovingBackground = false
    }

    private func drawingStep(canvasHeight: CGFloat) -> some View {
        // Space the painted edges, excluding the invisible portions of the hit targets.
        let toolInk = SketchOutline(radius: 12).path(in: CGRect(x: 0, y: 0, width: 44, height: 44))
            .boundingRect.insetBy(dx: -SketchInk.lineWidth / 2, dy: -SketchInk.lineWidth / 2)
        let canvasInk = SketchOutline(radius: 18).path(in: CGRect(x: 0, y: 0, width: 100, height: canvasHeight))
            .boundingRect.insetBy(dx: -SketchInk.lineWidth / 2, dy: -SketchInk.lineWidth / 2)
        let font = OGType.uiFont(18)
        let textTopInset = ["Undo", "Clear"].map { title in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: [.font: font]))
            return (44 - font.lineHeight) / 2 + font.ascender - CTLineGetImageBounds(line, nil).maxY
        }.min() ?? 0
        return VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    SketchOutline(radius: 18).fill(Color.ogPaper)
                    // The isolated object is underneath the transparent drawing canvas.
                    // Both layers will be saved together as the guardian artwork.
                    if let reference = isolatedObject ?? (useOriginalImage ? referenceImage : nil) {
                        Image(uiImage: reference)
                            .resizable()
                            .scaledToFit()
                            // Match the saved composite's centered 20 pt inset.
                            .frame(width: max(0, geo.size.width - 40), height: max(0, geo.size.height - 40))
                            .frame(width: geo.size.width, height: geo.size.height)
                            .allowsHitTesting(false)
                    }
                    DrawingPad(
                        drawing: $drawing, brush: ink.color, isEraser: erasing,
                        undoSignal: undoCounter, clearSignal: clearCounter
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(SketchOutline(radius: 18).stroke(Color.black, style: SketchInk.strokeStyle))
                .clipped()
                .accessibilityIdentifier("guardian-drawing-canvas")
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
            }
            .padding(.horizontal, OGLayout.screenMargin)
            .frame(height: canvasHeight)
            Spacer().frame(height: OGLayout.sectionGap - max(0, canvasHeight - canvasInk.maxY) - toolInk.minY)
            HStack(spacing: 0) {
                HStack(spacing: OGLayout.sectionGap) {
                    Button {
                        erasing = false
                    } label: {
                        Image("drawing-pen").renderingMode(.original).resizable().scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(width: 44, height: 44)
                            .background(SketchOutline(radius: 12).fill(!erasing ? Color.ogButter : Color.ogPaper))
                            .overlay(SketchOutline(radius: 12).stroke(.black, style: SketchInk.strokeStyle))
                    }
                    .accessibilityLabel("Pen")
                    Button {
                        erasing = true
                    } label: {
                        Image("drawing-eraser").renderingMode(.original).resizable().scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(width: 44, height: 44)
                            .background(SketchOutline(radius: 12).fill(erasing ? Color.ogButter : Color.ogPaper))
                            .overlay(SketchOutline(radius: 12).stroke(.black, style: SketchInk.strokeStyle))
                    }
                    .accessibilityLabel("Eraser")
                }
                Spacer(minLength: OGLayout.gap)
                // Account for the 44 pt targets around 40 pt circles: 24 pt visible gaps.
                HStack(spacing: OGLayout.sectionGap - OGLayout.controlGap) {
                    ForEach(BrushColor.allCases) { option in
                        Button {
                            ink = option; erasing = false
                        } label: {
                            SketchCapsule()
                                .fill(Color(uiColor: option.color))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if ink == option && !erasing {
                                        SketchCapsule().stroke(Color.ogInk, style: SketchInk.strokeStyle)
                                    }
                                }
                                .frame(width: 44, height: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(option.rawValue)
                        .accessibilityAddTraits(ink == option && !erasing ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, OGLayout.screenMargin)
            .frame(height: 44)
            .foregroundColor(.black)
            .buttonStyle(.plain)
            Spacer().frame(height: OGLayout.sectionGap - (44 - toolInk.maxY) - textTopInset)
            HStack {
                Button("Undo") { undoCounter += 1 }.frame(minWidth: 44, minHeight: 44)
                Spacer()
                Button("Clear") { clearCounter += 1 }.frame(minWidth: 44, minHeight: 44)
            }
            .font(OGType.font(18))
            .padding(.horizontal, OGLayout.screenMargin + OGLayout.controlGap)
            .padding(.bottom, OGLayout.actionTop)
            .foregroundColor(.black)
            Spacer(minLength: 0)
        }
    }

    private var saveStep: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable().scaledToFit()
                            .frame(height: namingCanvasHeight)
                            .frame(maxWidth: .infinity)
                            .background(SketchOutline(radius: 16).fill(Color.ogPaper))
                            .overlay(SketchOutline(radius: 16).stroke(.black, style: SketchInk.strokeStyle))
                    }
                    VStack(spacing: 0) {
                        Spacer().frame(height: OGLayout.sectionGap)
                        VStack(spacing: OGLayout.sectionGap) {
                            SketchField(label: "Guardian name", text: $guardianName, placeholder: "e.g. Momo")
                            SketchField(label: "Object (optional)", text: $objectName, placeholder: "e.g. My favorite cup")
                        }
                        Spacer(minLength: OGLayout.gap)
                    }
                    // Keep remaining space below the fields without enlarging the top gap.
                    .frame(minHeight: max(OGLayout.namingFieldsHeight,
                                          geometry.size.height - namingCanvasHeight) + OGLayout.actionTop,
                           alignment: .top)
                }
                .padding(.horizontal, OGLayout.screenMargin)
            }
            .ogScrollBehindBottomControls()
        }
    }

    private func finishedStep(canvasHeight: CGFloat) -> some View {
            ScrollView {
                VStack(spacing: OGLayout.sectionGap) {
                    if let image = preview {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(height: canvasHeight)
                            .frame(maxWidth: .infinity)
                            .background(SketchOutline(radius: 16).fill(Color.ogPaper))
                            .overlay(SketchOutline(radius: 16).stroke(Color.ogInk, style: SketchInk.strokeStyle))
                    }
                    Text("Welcome home, \(created?.name ?? "little friend")!")
                        .font(OGType.section)
                        .multilineTextAlignment(.center)
                    Text(
                        "\(created?.name ?? "Your guardian") is now wandering around your\nHome and waiting on your Shelf."
                    )
                    .font(OGType.body)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, OGLayout.screenMargin)
                .padding(.bottom, OGLayout.gap)
            }
            .ogScrollBehindBottomControls()
    }

    private var prepareAction: some View {
        SketchButton(
            label: "Start drawing", prominent: true, illustration: "screen-right", illustrationPlacement: .trailing
        ) {
            setStep(1)
        }
        .accessibilityIdentifier("create-start-drawing")
        .disabled(isRemovingBackground || (isolatedObject == nil && !useOriginalImage))
        .opacity(isRemovingBackground || (isolatedObject == nil && !useOriginalImage) ? 0.45 : 1)
    }

    private var nextAction: some View {
        SketchButton(label: "Next", prominent: true, illustration: "screen-right", illustrationPlacement: .trailing) {
            guard !drawing.strokes.isEmpty else {
                errorText = "Draw your guardian first!"
                return
            }
            guard let image = isolatedObject ?? (useOriginalImage ? referenceImage : nil) else {
                errorText = "Please finish preparing your object first."
                return
            }
            // Export at the same canvas size as the PencilKit view so
            // the ink stays aligned with the object when composited.
            let size = canvasSize
            let canvasRect = CGRect(origin: .zero, size: size)
            let inkOnly = drawing.image(from: canvasRect, scale: 2.0)
            inkPreview = inkOnly
            preview = GuardianArtworkComposite.render(
                isolatedObject: image,
                ink: inkOnly,
                canvasSize: size
            )
            setStep(2)
        }
        .accessibilityIdentifier("create-next")
    }

    private var saveAction: some View {
        SketchButton(
            label: "Save guardian", prominent: true, illustration: "screen-right", illustrationPlacement: .trailing
        ) {
            guard !guardianName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let image = preview
            else {
                errorText = "Give your guardian a name first."
                return
            }
            guard let inkPreview,
                let objectCutout = isolatedObject ?? (useOriginalImage ? referenceImage : nil),
                let guardian = store.addGuardian(
                    name: guardianName,
                    objectName: objectName,
                    reference: referenceImage,
                    drawing: drawing,
                    drawingImage: image,
                    inkImage: inkPreview,
                    cutoutImage: objectCutout
                )
            else {
                errorText = "Could not save. Please try again."
                return
            }
            created = guardian
            setStep(3)
        }
        .accessibilityIdentifier("create-save")
    }

    private var finishedActions: some View {
        HStack(spacing: OGLayout.buttonPairGap) {
            SketchButton(label: "Done", prominent: onFindAgain == nil) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { dismiss() }
            }
                .accessibilityIdentifier("create-done")
            if let onFindAgain {
                SketchButton(label: "Say hello again", prominent: true) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: onFindAgain)
                }
                .accessibilityIdentifier("create-find-again")
            }
        }
    }

    #if DEBUG
    @MainActor
    fileprivate static func preview(step: Int, store: GuardianStore) -> Self {
        let guardian = store.guardians[0]
        var screen = Self(referenceImage: store.reference(for: guardian)!, onFindAgain: {})
        screen._step = State(initialValue: step)
        screen._isolatedObject = State(initialValue: store.cutout(for: guardian))
        screen._preview = State(initialValue: store.drawing(for: guardian))
        screen._inkPreview = State(initialValue: store.overlay(for: guardian))
        screen._created = State(initialValue: guardian)
        screen._guardianName = State(initialValue: guardian.name)
        screen._objectName = State(initialValue: guardian.objectName)
        screen.isPreview = true
        return screen
    }
    #endif
}

#if DEBUG
@MainActor
private struct CreationScreenPreview: View {
    @StateObject private var store = HomePreviewFixtures.makeStore(occupied: true)
    let step: Int

    var body: some View {
        CreateGuardianFlow.preview(step: step, store: store)
            .environmentObject(store)
            .font(OGType.body)
            .preferredColorScheme(.light)
    }
}

#Preview("Create · Prepare object") { CreationScreenPreview(step: 0) }
#Preview("Create · Draw on object") { CreationScreenPreview(step: 1) }
#Preview("Create · Name guardian") { CreationScreenPreview(step: 2) }
#Preview("Create · Welcome home") { CreationScreenPreview(step: 3) }
#endif

// MARK: - On-device foreground isolation (iOS 17+)

/// Vision detects foreground instances. Core Image uses the mask to make
/// the original background transparent. The original full camera photo is
/// still saved by GuardianStore for object recognition.
private enum ForegroundCutout {
    enum Failure: Error {
        case missingImage
        case noForeground
        case renderingFailed
    }

    static func create(from image: UIImage) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            try ForegroundCutout.isolate(image)
        }.value
    }

    private static func isolate(_ image: UIImage) throws -> UIImage {
        // Normalize camera orientation before obtaining the mask.
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let source = CIImage(image: upright) else {
            throw Failure.missingImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: source, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first,
              !result.allInstances.isEmpty else {
            throw Failure.noForeground
        }

        // For the MVP, use all detected foreground objects. In a busy scene,
        // the user may need to recapture with one clear central subject.
        let maskBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let transparent = CIImage(color: CIColor.clear).cropped(to: source.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = transparent
        blend.maskImage = mask

        guard let output = blend.outputImage,
              let cutout = CIContext().createCGImage(output, from: source.extent) else {
            throw Failure.renderingFailed
        }
        return UIImage(cgImage: cutout, scale: upright.scale, orientation: .up)
    }
}

// MARK: - Full transparent artwork: object + guardian ink

/// Uses the same aspect-fit placement and 20-point inset as drawingStep.
/// The background is transparent. The result is the combined artwork
/// shown in Home, Shelf, and Guardian Profile.
private enum GuardianArtworkComposite {
    static func render(isolatedObject: UIImage, ink: UIImage, canvasSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = false
        let bounds = CGRect(origin: .zero, size: canvasSize)
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            let inner = bounds.insetBy(dx: 20, dy: 20)
            let widthRatio = inner.width / max(1, isolatedObject.size.width)
            let heightRatio = inner.height / max(1, isolatedObject.size.height)
            let ratio = min(widthRatio, heightRatio)
            let width = isolatedObject.size.width * ratio
            let height = isolatedObject.size.height * ratio
            let target = CGRect(
                x: inner.midX - width / 2,
                y: inner.midY - height / 2,
                width: width,
                height: height
            )
            isolatedObject.draw(in: target)
            ink.draw(in: bounds)
        }
    }
}
