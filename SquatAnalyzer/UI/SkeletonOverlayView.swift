import SwiftUI
import Vision

/// Draws the detected skeleton over the camera preview.
///
/// Pose points are normalized to the captured image; the preview uses
/// aspect-fill, so the same fill transform is applied here to keep the
/// skeleton aligned with the video.
struct SkeletonOverlayView: View {
    let pose: DetectedPose
    /// Bottom-position targets, drawn as rings the athlete steers into.
    var reference: ReferencePose?

    private static let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
    ]

    private static let highlightedJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftKnee, .rightKnee, .leftHip, .rightHip, .leftAnkle, .rightAnkle,
    ]

    var body: some View {
        Canvas { context, size in
            if let reference {
                drawReferenceRings(reference, in: &context, size: size)
            }

            for (from, to) in Self.bones {
                guard let a = pose[from], let b = pose[to] else { continue }
                var path = Path()
                path.move(to: viewPoint(for: a, in: size))
                path.addLine(to: viewPoint(for: b, in: size))
                context.stroke(path, with: .color(.green.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            for (name, point) in pose.joints {
                let center = viewPoint(for: point, in: size)
                let isKeyJoint = Self.highlightedJoints.contains(name)
                let radius: CGFloat = isKeyJoint ? 7 : 5
                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(isKeyJoint ? .yellow : .white))
            }
        }
        .allowsHitTesting(false)
    }

    /// Dashed rings at each target joint position. A ring turns green and fills
    /// when the matching live joint is inside it, so the athlete can steer
    /// their posture into the targets mid-rep.
    private func drawReferenceRings(_ reference: ReferencePose,
                                    in context: inout GraphicsContext,
                                    size: CGSize) {
        let radius = ringRadius(in: size)
        guard radius > 0 else { return }

        for (joint, target) in reference.targets {
            let center = viewPoint(for: target, in: size)
            let onTarget: Bool
            if let live = pose[joint] {
                let livePoint = viewPoint(for: live, in: size)
                onTarget = hypot(livePoint.x - center.x, livePoint.y - center.y) <= radius
            } else {
                onTarget = false
            }

            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            let ring = Path(ellipseIn: rect)
            if onTarget {
                context.fill(ring, with: .color(.green.opacity(0.25)))
            }
            context.stroke(ring,
                           with: .color(onTarget ? .green : .cyan.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
        }
    }

    /// The on-screen ring radius matching the normalized hit tolerance.
    private func ringRadius(in viewSize: CGSize) -> CGFloat {
        let imageSize = pose.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        return ReferencePose.tolerance * imageSize.height * scale
    }

    /// Maps a normalized image point into view coordinates under aspect-fill.
    private func viewPoint(for normalized: CGPoint, in viewSize: CGSize) -> CGPoint {
        let imageSize = pose.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let xOffset = (viewSize.width - scaledWidth) / 2
        let yOffset = (viewSize.height - scaledHeight) / 2

        return CGPoint(x: normalized.x * scaledWidth + xOffset,
                       y: normalized.y * scaledHeight + yOffset)
    }
}
