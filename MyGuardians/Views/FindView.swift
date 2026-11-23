import SwiftUI
import UIKit

struct FindView: View {
    private enum CameraMode: Equatable { case create, recognize }

    @EnvironmentObject private var store: GuardianStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraManager()

    var selectedGuardianID: UUID? = nil
    var standalone: Bool = false

    @State private var cameraMode: CameraMode?
    @State private var manuallySelectedID: UUID?
    @State private var rejectedGuardianIDs: Set<UUID> = []
    @State private var isManualPreview = false
    @State private var isARMode = false
    @State private var activeDemo = false
    @State private var creation: CreationDraft?
    @State private var memory: MemoryDraft?
    @State private var profile: Guardian?
    @State private var overlayPosition = CGPoint(x: 0.52, y: 0.43)
    @State private var overlayScale: CGFloat = 1.0
    @State private var cameraPreviewBounds: CGRect = .zero
    @State private var drawingViewportBounds: CGRect = .zero
    @GestureState private var livePinch: CGFloat = 1.0
    @State private var overlayRotation: Angle = .zero
    @GestureState private var liveRotation: Angle = .zero
    @State private var warning: String?
    @State private var showingInfo = false
    @State private var recognitionFallbackUsed = false
    @State private var acknowledgedCameraPermission = false
    private var isPreview = false

    init(selectedGuardianID: UUID? = nil, standalone: Bool = false) {
        self.selectedGuardianID = selectedGuardianID
        self.standalone = standalone
        _cameraMode = State(initialValue: selectedGuardianID != nil || standalone ? .recognize : nil)
    }

    #if DEBUG
    fileprivate init(previewState: FindPreviewState, guardian: Guardian?) {
        isPreview = true
        _cameraMode = State(initialValue: previewState == .landing ? nil : previewState == .create ? .create : .recognize)
        _activeDemo = State(initialValue: previewState != .landing)
        _manuallySelectedID = State(initialValue: previewState == .confirmation || previewState == .overlay ? guardian?.id : nil)
        _isARMode = State(initialValue: previewState == .overlay)
        _isManualPreview = State(initialValue: previewState == .overlay)
    }
    #endif

    private var selectedID: UUID? {
        if let manuallySelectedID { return manuallySelectedID }
        if let preferred = selectedGuardianID {
            // Launching from a profile means "look for this object", not "already found".
            if manuallySelectedID == preferred ||
                (camera.autoMatch?.guardianID == preferred && !rejectedGuardianIDs.contains(preferred)) {
                return preferred
            }
            return nil
        }
        guard let automaticID = camera.autoMatch?.guardianID,
              !rejectedGuardianIDs.contains(automaticID) else { return nil }
        return automaticID
    }
    private var activeGuardian: Guardian? {
        selectedID.flatMap { store.guardian($0) }
    }
    var body: some View {
        Group {
            if cameraMode == nil { landing }
            else { cameraScreen }
        }
        .background(cameraMode == nil ? Color.ogBackground : Color.clear)
.presentationBackground(cameraMode == nil ? Color.ogBackground : Color.clear)
        .onAppear { showingInfo = false; updateCameraLifecycle() }
        .onDisappear { showingInfo = false; camera.stop() }
        .onChange(of: cameraMode) { showingInfo = false; updateCameraLifecycle() }
        .onChange(of: isARMode) { showingInfo = false }
        .onChange(of: activeGuardian?.id) { _, id in
            if cameraMode == .recognize, id != nil { recognitionFallbackUsed = true }
        }
        .task(id: cameraMode == .recognize && !isARMode && !activeDemo) {
            guard cameraMode == .recognize, !isARMode, !activeDemo,
                  !isPreview, !recognitionFallbackUsed else { return }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            guard !Task.isCancelled, cameraMode == .recognize, !isARMode,
                  !recognitionFallbackUsed, activeGuardian == nil else { return }
            recognitionFallbackUsed = true
            guard let latest = store.guardians.max(by: { $0.createdAt < $1.createdAt }) else { return }
            manuallySelectedID = latest.id
        }
        .onChange(of: store.guardians.count) { updateReferences() }
        .fullScreenCover(item: $creation, onDismiss: { updateCameraLifecycle() }) { draft in
            CreateGuardianFlow(referenceImage: draft.reference, onFindAgain: {
                enterCamera(.recognize)
            })
            .environmentObject(store)
        }
        .sheet(item: $memory) { draft in
            SaveMemoryView(draft: draft) {
                memory = nil
                DispatchQueue.main.asyncAfter(deadline:.now()+0.45) {
                    profile = store.guardian(draft.guardianID)
                }
            }
            .environmentObject(store)
        }
        .guardianProfileSheet(selection: $profile)
        .confirmationDialog("Information", isPresented: $showingInfo, titleVisibility: .visible) {
            if cameraMode == nil {
                Button("Try demo object") { activeDemo = true; enterCamera(.create) }
            }
            if cameraMode != nil {
                if !activeDemo {
                    Button("Try demo object") {
                        activeDemo = true
                        updateCameraLifecycle()
                    }
                        .accessibilityIdentifier("find-demo")
                }
                if cameraMode == .recognize {
                    if !isARMode {
                        Button("Try demo recognition") { simulateRecognition() }
                            .accessibilityIdentifier("find-demo-recognition")
                            .disabled(store.guardians.isEmpty)
                    }
                    Button("Reset guardian placement") { resetOverlay() }
                        .accessibilityIdentifier("find-reset-overlay")
                    if !isARMode {
                        Button("Check for saved guardians") { rescan() }
                            .accessibilityIdentifier("find-rescan")
                        if let preferred = selectedGuardianID, let wanted = store.guardian(preferred) {
                            Button("Preview \(wanted.name) manually") { previewManually(wanted) }
                                .accessibilityIdentifier("find-manual-\(wanted.id)")
                        } else {
                            ForEach(store.guardians) { guardian in
                                Button("Preview \(guardian.name) manually") { previewManually(guardian) }
                                    .accessibilityIdentifier("find-manual-\(guardian.id)")
                            }
                        }
                    }
                    Button("Meet a new friend") { enterCamera(.create) }
                } else if !store.guardians.isEmpty {
                    Button("Say hello again") { enterCamera(.recognize) }
                }
            }
            Button("Got it") { showingInfo = false }
        } message: {
            Text(informationMessage)
        }
        .alert("Camera or capture issue", isPresented: Binding(
            get: { warning != nil || (cameraMode != nil && !activeDemo && camera.permissionDenied && !acknowledgedCameraPermission) },
            set: { if !$0 { warning = nil; acknowledgedCameraPermission = true } }
        )) {
            Button("OK", role: .cancel) { warning = nil; acknowledgedCameraPermission = true }
        } message: {
            Text(warning ?? "Allow Camera access in iPhone Settings, or open Information to try the demo object.")
        }
    }

    private var landing: some View {
        VStack(spacing: 0) {
            SketchHeader(title: "Find your guardian", titleAlignment: .leading,
                         trailingAsset: "screen-info", trailingAction: { showingInfo = true },
                         trailingAccessibilityLabel: "About finding guardians")
                .ogScreenHeader()
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 24)
                        destinationCard(
                            title: "Meet a new friend", illustration: "find-net",
                            detail: "Every object has a little guardian.\nFind one and bring yours to life with a drawing.",
                            enabled: true
                        ) { enterCamera(.create) }
                        .accessibilityIdentifier("find-create")
                        destinationCard(
                            title: "Say hello again", illustration: "find-reunion",
                            detail: "Find a saved object, reunite with its guardian,\nand capture a little memory together.",
                            enabled: !store.guardians.isEmpty,
                            illustrationSize: 56
                        ) { activeDemo = false; enterCamera(.recognize) }
                        .accessibilityIdentifier("find-recognize")
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 28)
                    .frame(minHeight: geometry.size.height)
                }
                .ogScrollBehindBottomControls()
            }
        }
        .foregroundColor(.ogInk)
    }

    private func destinationCard(title: String, illustration: String, detail: String,
                                 enabled: Bool, illustrationSize: CGFloat = 44, action: @escaping () -> Void) -> some View {
        let card = Button(action: action) {
            SketchCard(content: VStack(spacing: 16) {
                Image(illustration)
                    .renderingMode(.original)
                    .resizable().scaledToFit()
                    .frame(width: illustrationSize, height: illustrationSize)
                    .accessibilityHidden(true)
                Text(title).font(OGType.section)
                Text(detail)
                    .font(OGType.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 188), fill: enabled ? .ogPaper : .clear)
        }
        return Group {
            if enabled {
                card.buttonStyle(.plain)
            } else {
                card.buttonStyle(FullInkCardButtonStyle()).disabled(true)
            }
        }
        .foregroundStyle(Color.ogInk)
        .accessibilityLabel(title)
        .accessibilityHint(enabled ? detail.replacingOccurrences(of: "\n", with: " ") : "Save your first guardian to say hello again.")
    }

    private var cameraScreen: some View {
    ZStack {
        Group {
                if activeDemo {
                    GeometryReader { geo in
                        Image(uiImage: DemoArtwork.mugPhoto())
                            .resizable().scaledToFill()
                            .frame(width:geo.size.width,height:geo.size.height)
                            .clipped()
                    }
                } else {
                    CameraPreview(session: camera.session)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                cameraPreviewBounds = $0
            }
            .ignoresSafeArea(edges: .all)
            if isARMode, let guardian = activeGuardian,
               let inkOnly = store.overlay(for: guardian) {
                GeometryReader { geo in
                    Image(uiImage: inkOnly)
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(geo.size.width * 0.36, 155),height:min(geo.size.width * 0.36, 155))
                        .scaleEffect(overlayScale * livePinch)
                        .rotationEffect(overlayRotation + liveRotation)
                        .position(x: geo.size.width * overlayPosition.x,
                                  y: geo.size.height * overlayPosition.y)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("guardianCamera")).onChanged { drag in
                            overlayPosition = CGPoint(
                                x: min(0.88,max(0.12,drag.location.x / geo.size.width)),
                                y: min(0.82,max(0.14,drag.location.y / geo.size.height))
                            )
                        })
                        .simultaneousGesture(
                            MagnificationGesture()
                                .updating($livePinch) { value, state, _ in state = value }
                                .onEnded { value in
                                    overlayScale = min(2.7, max(0.4, overlayScale * value))
                                }
                        )
                        .simultaneousGesture(
                            RotationGesture()
                                .updating($liveRotation) { value, state, _ in state = value }
                                .onEnded { value in overlayRotation += value }
                        )
                        .accessibilityLabel("\(guardian.name) floating in the camera")
                }
                .coordinateSpace(name: "guardianCamera")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    drawingViewportBounds = $0
                }
            }
            VStack(spacing: 16) {
                cameraHeader
                ZStack(alignment: .bottom) {
                    SketchOutline(radius: 22)
                        .stroke(Color.ogButter, style: SketchInk.strokeStyle)
                        .allowsHitTesting(false)
                    if isARMode {
                        Text("Drag · Pinch · Rotate")
                            .font(OGType.font(18))
                            .multilineTextAlignment(.center)
                            .modifier(CameraTextLabelStyle())
                            .padding(.bottom, 14)
                    } else if cameraMode == .recognize && activeGuardian == nil {
                        Text(selectedGuardianID == nil ? "Looking for a saved object…" : "Looking for this guardian's object…")
                            .font(OGType.font(18))
                            .multilineTextAlignment(.center)
                            .modifier(CameraTextLabelStyle())
                            .padding(.bottom, 14)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
                if isARMode { captureControls }
                else if cameraMode == .create {
                    SketchButton(label: "Create guardian", prominent: true, illustration: "screen-plus") {
                        startCreation()
                    }
                    .accessibilityIdentifier("find-capture-object")
                    .offset(y: standalone ? 0 : OGLayout.actionBottom + OGLayout.actionTop - OGLayout.primaryNavigationGap)
                } else { recognitionControls }
            }
            .padding(.horizontal, OGLayout.screenMargin)
            .padding(.top, OGLayout.headerTop)
            .padding(.bottom, OGLayout.actionBottom)
        }
    }

    private var cameraHeader: some View {
        HStack(spacing: 8) {
            cameraIcon("screen-back", label: "Back") { leaveCamera() }
            Text(isARMode ? "Keep this little moment" : cameraMode == .create ? "Meet a new friend" : "Let's find an old friend")
                .font(OGType.section)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .modifier(CameraTextLabelStyle())
                .frame(maxWidth: .infinity)
            cameraIcon("screen-close", label: "Close") { showingInfo = true }
        }
        .foregroundColor(.white)
        .frame(minHeight: OGLayout.headerHeight)
    }

    private func cameraIcon(_ asset: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset).renderingMode(.original).resizable().scaledToFit()
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var recognitionControls: some View {
        if let candidate = activeGuardian {
            SketchCard(content: HStack(spacing: OGLayout.gap) {
                GuardianArtwork(filename: candidate.drawingFile)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.25)
                    .frame(width: 64, height: 64)
                    .background(Color.ogPaper)
                    .accessibilityLabel("\(candidate.name)'s artwork")
                VStack(alignment: .leading, spacing: 16) {
                    Text("Is this \(candidate.name)?")
                        .font(OGType.section)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: OGLayout.buttonPairGap) {
                        SketchButton(label: "No", cornerRadius: 8, labelVerticalPadding: 8) {
                            recognitionFallbackUsed = true
                            manuallySelectedID = nil
                            camera.rejectRecognition(candidate.id)
                        }
                        .accessibilityIdentifier("find-reject-match")
                        SketchButton(label: "Yes", prominent: true, cornerRadius: 8, labelVerticalPadding: 8) {
                            manuallySelectedID = candidate.id
                            isManualPreview = false
                            isARMode = true
                        }
                        .accessibilityIdentifier("find-confirm-match")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }, contentInsets: EdgeInsets(top: 26, leading: 24, bottom: 26, trailing: 24))
            .accessibilityIdentifier("find-recognized-guardian")
        }
    }

    private var informationMessage: String {
        var message = cameraMode == .recognize
            ? "Point the camera at a saved object. Confirm its guardian, then drag, pinch, or rotate the drawing to take a photo. The drawing is a 2D camera overlay."
            : "Meet a new friend to photograph an object and draw its guardian. Say hello again to find a saved object and make a memory together."
        if activeDemo {
            message += "\n\nDemo mode is using a sample object instead of the live camera."
        }
        if isManualPreview {
            message += "\n\nManual preview · not a recognition result."
        }
        return message
    }

    private var captureControls: some View {
        Button(action: captureMemory) {
            SketchCapsule().fill(Color.ogPaper)
                .overlay(SketchCapsule().stroke(Color.ogInk, style: SketchInk.strokeStyle))
                .overlay(SketchCapsule().stroke(Color.ogInk, style: SketchInk.strokeStyle).padding(6))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture memory")
        .accessibilityIdentifier("find-capture-memory")
        .frame(maxWidth: .infinity)
    }

    private func enterCamera(_ mode: CameraMode) {
        recognitionFallbackUsed = false
        camera.resetRecognition()
        isARMode = false
        manuallySelectedID = nil
        isManualPreview = false
        rejectedGuardianIDs.removeAll()
        acknowledgedCameraPermission = false
        resetOverlay()
        cameraMode = mode
    }

    private func leaveCamera() {
        if isARMode {
            isARMode = false
            manuallySelectedID = nil
            isManualPreview = false
            resetOverlay()
        } else if standalone { dismiss() }
        else { cameraMode = nil }
    }

    private func simulateRecognition() {
        showingInfo = false
        guard let guardian = selectedGuardianID.flatMap({ store.guardian($0) }) ?? store.guardians.first else { return }
        activeDemo = false
        isARMode = false
        isManualPreview = true
        camera.resetRecognition()
        rejectedGuardianIDs.remove(guardian.id)
        manuallySelectedID = guardian.id
        resetOverlay()
        updateCameraLifecycle()
    }

    private func previewManually(_ guardian: Guardian) {
        manuallySelectedID = guardian.id
        isManualPreview = true
        isARMode = true
    }

    private func rescan() {
        rejectedGuardianIDs.removeAll()
        if activeDemo { camera.recognizeDemoObject(DemoArtwork.mugPhoto()) }
        else { camera.checkNow() }
    }

    private func updateReferences() {
        guard !isPreview else { return }
        camera.updateReferences(store.guardians.compactMap { guardian in
            store.reference(for: guardian).map { (guardian.id, $0) }
        })
    }

    private func updateCameraLifecycle() {
        updateReferences()
        if cameraMode != nil && !activeDemo && !isPreview { camera.start() }
        else { camera.stop() }
        if cameraMode == .recognize && activeDemo && !isPreview {
            camera.recognizeDemoObject(DemoArtwork.mugPhoto())
        }
    }

    private func resetOverlay() {
        overlayPosition = CGPoint(x: 0.52, y: 0.43)
        overlayScale = 1
        overlayRotation = .zero
    }

    private func startCreation() {
        if activeDemo { presentCreation(reference: DemoArtwork.mugPhoto()); return }
        guard let frame = camera.latestFrame else {
            warning = "Point the camera at your object first, or open Information to try the demo object."
            return
        }
        presentCreation(reference: frame)
    }

    private func presentCreation(reference: UIImage) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            creation = CreationDraft(reference: reference)
        }
    }

    private func captureMemory() {
        guard let guardian = activeGuardian,
              let drawing = store.overlay(for: guardian) else {
            warning = "Guardian drawing is unavailable."
            return
        }
        let frame = activeDemo ? DemoArtwork.mugPhoto() : camera.latestFrame
        guard let frame else { warning = "The camera isn't ready yet."; return }
        guard cameraPreviewBounds.width > 0, cameraPreviewBounds.height > 0,
              drawingViewportBounds.width > 0, drawingViewportBounds.height > 0 else { return }
        let composite = SnapshotComposite.render(
            photo: frame, drawing: drawing,
            previewBounds: cameraPreviewBounds, drawingBounds: drawingViewportBounds,
            position: overlayPosition, scale: overlayScale * livePinch,
            rotation: overlayRotation + liveRotation
        )
        memory = MemoryDraft(guardianID: guardian.id, composite: composite)
    }
}

#if DEBUG
fileprivate enum FindPreviewState: Equatable { case landing, create, confirmation, overlay }

@MainActor
private struct FindScreenPreview: View {
    @StateObject private var store: GuardianStore
    let state: FindPreviewState

    init(occupied: Bool, state: FindPreviewState = .landing) {
        _store = StateObject(wrappedValue: HomePreviewFixtures.makeStore(occupied: occupied))
        self.state = state
    }

    var body: some View {
        FindView(previewState: state, guardian: store.guardians.first)
            .environmentObject(store)
    }
}

#Preview("Find · Empty") { FindScreenPreview(occupied: false) }
#Preview("Find · Saved guardians") { FindScreenPreview(occupied: true) }
#Preview("Find · Capture object") { FindScreenPreview(occupied: false, state: .create) }
#Preview("Find · Confirm sample guardian") { FindScreenPreview(occupied: true, state: .confirmation) }
#Preview("Find · 2D camera preview") { FindScreenPreview(occupied: true, state: .overlay) }
#endif

private struct ViewfinderCorners: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, d: CGFloat = 30
            for (x,y,sx,sy) in [(0.0,0.0,1.0,1.0),(1.0,0.0,-1.0,1.0),(0.0,1.0,1.0,-1.0),(1.0,1.0,-1.0,-1.0)] {
                var p = Path()
                p.move(to:CGPoint(x:w*x+sx*d,y:h*y))
                p.addLine(to:CGPoint(x:w*x,y:h*y))
                p.addLine(to:CGPoint(x:w*x,y:h*y+sy*d))
                context.stroke(p,with:.color(.white),style:StrokeStyle(lineWidth:3,lineCap:.round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum SnapshotComposite {
    static func render(photo: UIImage, drawing: UIImage,
                       previewBounds: CGRect, drawingBounds: CGRect, position: CGPoint,
                       scale: CGFloat, rotation: Angle) -> UIImage {
        let size = previewBounds.size
        let fillScale = max(size.width / photo.size.width, size.height / photo.size.height)
        let photoSize = CGSize(width: photo.size.width * fillScale, height: photo.size.height * fillScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = photo.scale / fillScale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // Match AVCaptureVideoPreviewLayer.resizeAspectFill's centered crop.
            photo.draw(in: CGRect(x: (size.width - photoSize.width) / 2,
                                  y: (size.height - photoSize.height) / 2,
                                  width: photoSize.width, height: photoSize.height))
            let cg = context.cgContext
            // Match the live drawing's aspect-fit square before its gesture transforms.
            let side = min(drawingBounds.width * 0.36, 155)
            let fitScale = min(side / max(drawing.size.width, 1), side / max(drawing.size.height, 1)) * scale
            let width = drawing.size.width * fitScale
            let height = drawing.size.height * fitScale
            cg.translateBy(x: drawingBounds.minX - previewBounds.minX + drawingBounds.width * position.x,
                           y: drawingBounds.minY - previewBounds.minY + drawingBounds.height * position.y)
            cg.rotate(by: CGFloat(rotation.radians))
            drawing.draw(in: CGRect(x: -width / 2, y: -height / 2,
                                    width: width, height: height))
        }
    }
}

private enum DemoArtwork {
    static func mugPhoto() -> UIImage {
        let size = CGSize(width:600,height:800)
        return UIGraphicsImageRenderer(size:size).image { ctx in
            let c = ctx.cgContext
            UIColor(red:0.96,green:0.94,blue:0.89,alpha:1).setFill()
            c.fill(CGRect(origin:.zero,size:size))
            UIColor(red:0.81,green:0.75,blue:0.64,alpha:1).setFill()
            c.fill(CGRect(x:0,y:530,width:600,height:270))
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(7)
            c.strokeEllipse(in:CGRect(x:380,y:280,width:125,height:185))
            let cup = UIBezierPath(roundedRect:CGRect(x:145,y:300,width:285,height:260),cornerRadius:30)
            UIColor(red:0.93,green:0.85,blue:0.7,alpha:1).setFill()
            cup.fill()
            UIColor.black.setStroke()
            cup.lineWidth = 7
            cup.stroke()
            c.setLineWidth(4)
            c.strokeEllipse(in:CGRect(x:145,y:284,width:285,height:33))
            let text = "DEMO MUG"
            text.draw(at:CGPoint(x:223,y:400),withAttributes:[.font:OGType.uiFont(28),.foregroundColor:UIColor.black])
        }
    }
}

// Disabled Find cards retain their original black ink instead of PlainButtonStyle's dimming.
private struct FullInkCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
