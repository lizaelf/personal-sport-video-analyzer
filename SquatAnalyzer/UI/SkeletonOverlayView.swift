import SwiftUI
import Vision

/// Draws the detected skeleton over the camera preview.
///
/// Pose points are normalized to the captured image; the preview uses
/// aspect-fill, so the same fill transform is applied here to keep the
/// skeleton aligned with the video.
struct SkeletonOverlayView: View {
    let pose: DetectedPose
    /// Bottom-position targets, drawn as a ghost posture outline the athlete steers into.
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

    /// The subset of `bones` that the ghost reference outline draws — the
    /// torso/leg silhouette, skipping arms since the targets don't track them.
    private static let referenceBones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    private static let highlightedJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftKnee, .rightKnee, .leftHip, .rightHip, .leftAnkle, .rightAnkle,
    ]

    var body: some View {
        Canvas { context, size in
            if let reference {
                drawReferenceOutline(reference, in: &context, size: size)
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

    /// A dashed "ghost" posture outline at the target squat position: the
    /// same shoulder–hip–knee–ankle silhouette as the live skeleton, but
    /// drawn at the calibrated bottom-of-squat targets. Each joint marker
    /// turns green once the athlete's live joint is close enough to it, and
    /// a bone segment turns solid green once both its endpoints are on
    /// target — so the outline "fills in" green as posture is achieved.
    private func drawReferenceOutline(_ reference: ReferencePose,
                                      in context: inout GraphicsContext,
                                      size: CGSize) {
        let tolerance = onTargetRadius(in: size)
        guard tolerance > 0 else { return }

        var onTarget: [VNHumanBodyPoseObservation.JointName: Bool] = [:]
        for (joint, target) in reference.targets {
            guard let live = pose[joint] else {
                onTarget[joint] = false
                continue
            }
            let livePoint = viewPoint(for: live, in: size)
            let targetPoint = viewPoint(for: target, in: size)
            onTarget[joint] = hypot(livePoint.x - targetPoint.x, livePoint.y - targetPoint.y) <= tolerance
        }

        for (from, to) in Self.referenceBones {
            guard let a = reference.targets[from], let b = reference.targets[to] else { continue }
            let bothOnTarget = (onTarget[from] ?? false) && (onTarget[to] ?? false)

            var path = Path()
            path.move(to: viewPoint(for: a, in: size))
            path.addLine(to: viewPoint(for: b, in: size))
            context.stroke(path,
                           with: .color(bothOnTarget ? .green : .pink),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round,
                                              dash: bothOnTarget ? [] : [10, 7]))
        }

        for (joint, target) in reference.targets {
            let center = viewPoint(for: target, in: size)
            let isOnTarget = onTarget[joint] ?? false
            let radius: CGFloat = 10
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(isOnTarget ? .green : .pink))
        }
    }

    /// The on-screen distance matching the normalized "on target" tolerance.
    private func onTargetRadius(in viewSize: CGSize) -> CGFloat {
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
