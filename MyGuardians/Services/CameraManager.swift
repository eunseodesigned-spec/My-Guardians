import Foundation
import UIKit
import SwiftUI
import AVFoundation
import CoreImage

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var permissionDenied = false
    @Published private(set) var latestFrame: UIImage?
    @Published private(set) var autoMatch: RecognizedGuardian?
    @Published private(set) var possibleMatch: RecognizedGuardian?
    @Published private(set) var isReady = false

    private let sessionQueue = DispatchQueue(label: "og.camera.session")
    private let imageQueue = DispatchQueue(label: "og.camera.processing")
    private let ciContext = CIContext()
    private let matcher = VisionMatcher()
    private var hasConfigured = false
    private var lastProcessedAt: TimeInterval = 0
    private var lastMatchID: UUID?
    private var matchStreak = 0
    // Processing-queue state keeps a confirmed card stable across missed frames.
    private var confirmedMatch: RecognizedGuardian?
    private var rejectedMatches: [UUID: Int] = [:]
    // Main-queue guard also blocks results already queued when No was tapped.
    private var dismissedMatchIDs: Set<UUID> = []

    func updateReferences(_ references: [(UUID, UIImage)]) {
        imageQueue.async { [weak self] in self?.matcher.update(references) }
    }

    @MainActor
    func resetRecognition() {
        autoMatch = nil
        possibleMatch = nil
        dismissedMatchIDs.removeAll()
        imageQueue.async { [weak self] in
            self?.lastMatchID = nil
            self?.matchStreak = 0
            self?.confirmedMatch = nil
            self?.rejectedMatches.removeAll()
        }
    }

    @MainActor
    func rejectRecognition(_ guardianID: UUID) {
        dismissedMatchIDs.insert(guardianID)
        autoMatch = nil
        possibleMatch = nil
        imageQueue.async { [weak self] in
            guard let self else { return }
            self.confirmedMatch = nil
            self.lastMatchID = nil
            self.matchStreak = 0
            self.rejectedMatches[guardianID] = 0
        }
    }

    func start() {
        #if targetEnvironment(simulator)
        // Simulator has no camera. Use the "Try Demo Object" action in Find.
        DispatchQueue.main.async { self.isReady = false }
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.start() }
                else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
            return
        }
        guard status == .authorized else {
            DispatchQueue.main.async { self.permissionDenied = true }
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.hasConfigured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.isReady = self.session.isRunning }
        }
        #endif
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isReady = false }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration(); hasConfigured = true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.setSampleBufferDelegate(self, queue: imageQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    /// Match the explicit demo image against registered references, never an arbitrary guardian.
    func recognizeDemoObject(_ image: UIImage) {
        imageQueue.async { [weak self] in
            guard let self else { return }
            let match = self.matcher.closest(to: image)
            let accepted = match.flatMap { $0.distance < 0.48 ? $0 : nil }
            DispatchQueue.main.async {
                self.latestFrame = image
                self.autoMatch = accepted
                self.possibleMatch = accepted
            }
        }
    }

    /// Manual check, useful when automatic match does not trigger for a different angle.
    func checkNow() {
        guard let image = latestFrame else { return }
        imageQueue.async { [weak self] in
            guard let self else { return }
            let match = self.matcher.closest(to: image)
            DispatchQueue.main.async { self.possibleMatch = match }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessedAt > 1.25,
              let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessedAt = now
        let ci = CIImage(cvPixelBuffer: pixel)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let image = UIImage(cgImage: cg)
        let guess = matcher.closest(to: image)
        let confidentGuess = guess.flatMap { $0.distance < 0.48 ? $0 : nil }
        // Require three processed frames without the rejected object before rearming it.
        for id in Array(rejectedMatches.keys) {
            let absentFrames = confidentGuess?.guardianID == id ? 0 : (rejectedMatches[id] ?? 0) + 1
            if absentFrames >= 3 {
                rejectedMatches.removeValue(forKey: id)
                DispatchQueue.main.async { [weak self] in self?.dismissedMatchIDs.remove(id) }
            } else {
                rejectedMatches[id] = absentFrames
            }
        }
        if let guess = confidentGuess, rejectedMatches[guess.guardianID] == nil {
            if guess.guardianID == lastMatchID { matchStreak += 1 }
            else { lastMatchID = guess.guardianID; matchStreak = 1 }
        } else { lastMatchID = nil; matchStreak = 0 }
        if confirmedMatch == nil, matchStreak >= 2 {
            confirmedMatch = confidentGuess
        }
        let accepted = confirmedMatch
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestFrame = image
            if let accepted, !self.dismissedMatchIDs.contains(accepted.guardianID) {
                self.autoMatch = accepted
            }
            self.possibleMatch = guess
        }
    }
}

final class CameraLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.backgroundColor = UIColor(Color.ogBackground)
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: CameraLayerView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
    }
}
