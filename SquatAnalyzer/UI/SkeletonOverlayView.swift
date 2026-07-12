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

    private static let highlightedJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftKnee, .rightKnee, .leftHip, .rightHip, .leftAnkle, .rightAnkle,
    ]

    var body: some View {
        Canvas { context, size in
            if let reference {
                drawReferenceTargets(reference, in: &context, size: size)
            }

            for (from, to) in Self.bones {
                guard let a = pose[from], let b = pose[to] else { continue }
                var path = Path()
                path.move(to: viewPoint(for: a, in: size))
                path.addLine(to: viewPoint(for: b, in: size))
                context.stroke(path, with: .color(.green.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            // Knees and hips are drawn at the same size/shape as their
            // reference target circle/pill, so live and target are directly comparable.
            let targetRadius = onTargetRadius(in: size) * 0.6

            for (name, point) in pose.joints {
                guard name != .leftHip, name != .rightHip else { continue }
                let center = viewPoint(for: point, in: size)
                let isKnee = name == .leftKnee || name == .rightKnee
                let isKeyJoint = Self.highlightedJoints.contains(name)
                let radius: CGFloat = isKnee ? targetRadius : (isKeyJoint ? 7 : 5)
                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(isKeyJoint ? .yellow : .white))
            }

            if let leftHip = pose[.leftHip], let rightHip = pose[.rightHip] {
                let pill = pillPath(from: viewPoint(for: leftHip, in: size),
                                    to: viewPoint(for: rightHip, in: size),
                                    radius: targetRadius)
                context.fill(pill, with: .color(.yellow))
            }
        }
        .allowsHitTesting(false)
    }

    /// Static target shapes at the bottom-of-squat positions measured from
    /// the reference video and scaled to this athlete: one pill spanning both
    /// hip targets, one circle per knee (the spots to drive into — each fills
    /// green when hit), and a tiny dot per foot (where the feet should stay planted).
    private func drawReferenceTargets(_ reference: ReferencePose,
                                      in context: inout GraphicsContext,
                                      size: CGSize) {
        let tolerance = onTargetRadius(in: size)
        guard tolerance > 0 else { return }

        let targetRadius = tolerance * 0.6
        let footRadius = targetRadius / 10

        drawHipBar(reference, tolerance: tolerance, targetRadius: targetRadius,
                  in: &context, size: size)

        for joint: VNHumanBodyPoseObservation.JointName in [.leftKnee, .rightKnee] {
            guard let target = reference.targets[joint] else { continue }
            let center = viewPoint(for: target, in: size)
            let isOnTarget: Bool
            if let live = pose[joint] {
                let livePoint = viewPoint(for: live, in: size)
                isOnTarget = hypot(livePoint.x - center.x, livePoint.y - center.y) <= tolerance
            } else {
                isOnTarget = false
            }

            let rect = CGRect(x: center.x - targetRadius, y: center.y - targetRadius,
                              width: targetRadius * 2, height: targetRadius * 2)
            let circle = Path(ellipseIn: rect)
            if isOnTarget {
                context.fill(circle, with: .color(.green.opacity(0.4)))
            }
            context.stroke(circle,
                           with: .color(isOnTarget ? .green : .white),
                           style: StrokeStyle(lineWidth: 6))
        }

        for joint: VNHumanBodyPoseObservation.JointName in [.leftAnkle, .rightAnkle] {
            guard let target = reference.targets[joint] else { continue }
            let center = viewPoint(for: target, in: size)
            let rect = CGRect(x: center.x - footRadius, y: center.y - footRadius,
                              width: footRadius * 2, height: footRadius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
        }
    }

    /// One solid pill (rounded rectangle, corner radius 999 → fully rounded
    /// ends) spanning both hip targets, instead of two separate circles.
    /// Fills green once both hips are on target.
    private func drawHipBar(_ reference: ReferencePose,
                            tolerance: CGFloat,
                            targetRadius: CGFloat,
                            in context: inout GraphicsContext,
                            size: CGSize) {
        guard
            let leftTarget = reference.targets[.leftHip],
            let rightTarget = reference.targets[.rightHip]
        else { return }

        let leftPoint = viewPoint(for: leftTarget, in: size)
        let rightPoint = viewPoint(for: rightTarget, in: size)

        func isOnTarget(_ joint: VNHumanBodyPoseObservation.JointName, target: CGPoint) -> Bool {
            guard let live = pose[joint] else { return false }
            let livePoint = viewPoint(for: live, in: size)
            return hypot(livePoint.x - target.x, livePoint.y - target.y) <= tolerance
        }
        let bothOnTarget = isOnTarget(.leftHip, target: leftPoint) && isOnTarget(.rightHip, target: rightPoint)

        let pill = pillPath(from: leftPoint, to: rightPoint, radius: targetRadius)
        if bothOnTarget {
            context.fill(pill, with: .color(.green.opacity(0.4)))
        }
        context.stroke(pill,
                       with: .color(bothOnTarget ? .green : .white),
                       style: StrokeStyle(lineWidth: 6))
    }

    /// A pill (rounded rectangle, corner radius 999 → fully rounded ends)
    /// spanning two points with the given half-height radius — used for both
    /// the reference hip target and the live hip marker, so they match in shape.
    private func pillPath(from: CGPoint, to: CGPoint, radius: CGFloat) -> Path {
        let minX = min(from.x, to.x) - radius
        let maxX = max(from.x, to.x) + radius
        let midY = (from.y + to.y) / 2
        let rect = CGRect(x: minX, y: midY - radius,
                          width: maxX - minX, height: radius * 2)
        return Path(roundedRect: rect, cornerRadius: 999)
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
