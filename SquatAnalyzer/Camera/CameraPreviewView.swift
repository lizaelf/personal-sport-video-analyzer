import AVFoundation
import SwiftUI

/// SwiftUI wrapper around AVCaptureVideoPreviewLayer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        configure(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: PreviewView) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        configurePreviewConnection(view.previewLayer.connection)
    }

    private func configurePreviewConnection(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        let rotation: CGFloat = ProcessInfo.processInfo.isiOSAppOnMac ? 0 : 90
        if connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
