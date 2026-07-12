import AVFoundation
import CoreVideo
import os

/// Owns the AVCaptureSession for the front camera and delivers video frames.
///
/// Frames are delivered on a dedicated serial queue via `onFrame`. The output
/// connection is rotated to portrait and mirrored so the pixel buffers match
/// what the user sees in the (automatically mirrored) preview layer.
///
/// `@unchecked Sendable`: the type synchronizes all mutable state through
/// `sessionQueue`/`videoQueue`, so it is safe to hand across concurrency
/// domains even though the compiler can't prove it.
final class CameraManager: NSObject, @unchecked Sendable {

    private let log = Logger(subsystem: "com.golaunchlabs.SquatAnalyzer", category: "Camera")
    private var frameCount = 0

    enum SetupResult {
        case ready
        case permissionDenied
        case configurationFailed
    }

    let session = AVCaptureSession()

    /// Called on `videoQueue` for every captured frame that isn't dropped.
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// Called on `videoQueue` for every captured frame, for manual preview rendering.
    var onPreviewFrame: ((CVPixelBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.golaunchlabs.squatanalyzer.session")
    private let videoQueue = DispatchQueue(label: "com.golaunchlabs.squatanalyzer.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    func setUp() async -> SetupResult {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        log.debug("setUp: authorization status = \(status.rawValue, privacy: .public)")

        let authorized: Bool
        switch status {
        case .authorized:
            authorized = true
        case .notDetermined:
            log.debug("setUp: requesting camera access…")
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        log.debug("setUp: authorized = \(authorized, privacy: .public)")
        guard authorized else { return .permissionDenied }

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                let ok = configureSession()
                log.debug("setUp: configureSession returned \(ok, privacy: .public)")
                continuation.resume(returning: ok ? .ready : .configurationFailed)
            }
        }
    }

    func start() {
        sessionQueue.async { [self] in
            guard isConfigured, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configureSession() -> Bool {
        if isConfigured { return true }

        log.debug("configureSession: begin")
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Prefer 720p, but fall back to whatever the device supports (some
        // cameras, incl. Macs in Designed-for-iPad mode, may not offer 720p).
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            log.debug("configureSession: 720p unsupported, using .high")
            session.sessionPreset = .high
        }

        log.debug("configureSession: selecting camera")
        guard
            let device = bestAvailableCamera(),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            log.error("No usable video capture device found.")
            return false
        }
        log.debug("Using capture device \(device.localizedName, privacy: .public) position=\(device.position.rawValue)")
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { return false }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                // Mirror only the front camera, to match the mirrored preview.
                connection.isVideoMirrored = device.position == .front
            }
        }

        isConfigured = true
        return true
    }

    /// The app is built around a front-facing (selfie) view, so the front
    /// wide-angle camera is preferred. Falls back through any front camera, any
    /// discovered video camera, and finally the system default device.
    ///
    /// The last fallback matters when running as a "Designed for iPad" app on a
    /// Mac: the Mac's camera reports `position == .unspecified`, so the
    /// front-specific lookup returns nil, and `default(for: .video)` is what
    /// reliably resolves the built-in FaceTime camera there.
    private func bestAvailableCamera() -> AVCaptureDevice? {
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified)
        return discovery.devices.first(where: { $0.position == .front })
            ?? discovery.devices.first
            ?? AVCaptureDevice.default(for: .video)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCount += 1
        if frameCount % 30 == 1 {
            log.debug("Received camera frame #\(self.frameCount, privacy: .public)")
        }
        onFrame?(pixelBuffer)
        onPreviewFrame?(pixelBuffer)
    }
}
