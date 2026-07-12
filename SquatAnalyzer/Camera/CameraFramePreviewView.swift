import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Live preview by rendering captured frames directly.
///
/// On a Mac running the app in "Designed for iPad" mode, `AVCaptureVideoPreviewLayer`
/// often stays black even though frames arrive. Drawing the same pixel buffers that
/// feed pose detection keeps the preview in sync and works reliably there.
struct CameraFramePreviewView: UIViewRepresentable {
    let camera: CameraManager

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera)
    }

    func makeUIView(context: Context) -> FramePreviewUIView {
        let view = FramePreviewUIView()
        context.coordinator.previewView = view
        camera.onPreviewFrame = { [weak view] pixelBuffer in
            view?.display(pixelBuffer: pixelBuffer)
        }
        return view
    }

    func updateUIView(_ uiView: FramePreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: FramePreviewUIView, coordinator: Coordinator) {
        coordinator.camera.onPreviewFrame = nil
        coordinator.previewView = nil
    }

    final class Coordinator {
        let camera: CameraManager
        weak var previewView: FramePreviewUIView?

        init(camera: CameraManager) {
            self.camera = camera
        }
    }
}

final class FramePreviewUIView: UIView {
    private let imageLayer = CALayer()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderQueue = DispatchQueue(label: "com.golaunchlabs.squatanalyzer.preview-render",
                                            qos: .userInteractive)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageLayer.frame = bounds
    }

    func display(pixelBuffer: CVPixelBuffer) {
        renderQueue.async { [weak self] in
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = Self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            DispatchQueue.main.async {
                self?.imageLayer.contents = cgImage
            }
        }
    }
}
