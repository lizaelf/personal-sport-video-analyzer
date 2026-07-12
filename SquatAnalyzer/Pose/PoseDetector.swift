import CoreVideo
import Vision

/// A detected body pose in view-friendly coordinates:
/// normalized 0–1, origin at the top-left (Vision's bottom-left origin is flipped here).
struct DetectedPose: Equatable {
    var joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    var imageSize: CGSize

    subscript(joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        joints[joint]
    }
}

/// Runs Vision's human body pose request on camera frames.
///
/// A stateless value type so it can be used from the non-isolated camera
/// callback without crossing an actor boundary.
struct PoseDetector: Sendable {

    private static func minimumConfidence(for joint: VNHumanBodyPoseObservation.JointName) -> Float {
        switch joint {
        case .leftShoulder, .rightShoulder, .neck:
            0.2
        default:
            0.3
        }
    }

    func detectPose(in pixelBuffer: CVPixelBuffer) -> DetectedPose? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        guard
            (try? handler.perform([request])) != nil,
            let observation = request.results?.first,
            let recognized = try? observation.recognizedPoints(.all)
        else { return nil }

        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (name, point) in recognized {
            let threshold = Self.minimumConfidence(for: name)
            guard point.confidence > threshold else { continue }
            // Vision uses a bottom-left origin; flip Y for screen coordinates.
            joints[name] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }
        guard !joints.isEmpty else { return nil }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))
        return DetectedPose(joints: joints, imageSize: imageSize)
    }
}
