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
    var phase: SquatPhase = .standing

    private static let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
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
                context.stroke(path, with: .color(boneColor(from: from, to: to)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            let targetRadius = onTargetRadius(in: size) * 0.6
            let hipBarRadius = targetRadius * 0.35
            let shoulderRadius: CGFloat = 7

            for (name, point) in pose.joints {
                guard name != .leftHip, name != .rightHip else { continue }
                let center = viewPoint(for: point, in: size)

                if JointColors.shoulderJoints.contains(name) {
                    let rect = CGRect(x: center.x - shoulderRadius, y: center.y - shoulderRadius,
                                      width: shoulderRadius * 2, height: shoulderRadius * 2)
                    let dot = Path(ellipseIn: rect)
                    context.fill(dot, with: .color(JointColors.shoulder))
                    context.stroke(dot, with: .color(.white.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2))
                    continue
                }

                if JointColors.kneeJoints.contains(name) {
                    let rect = CGRect(x: center.x - targetRadius, y: center.y - targetRadius,
                                      width: targetRadius * 2, height: targetRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(JointColors.knee))
                    continue
                }

                let radius: CGFloat = 5
                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }

            if let leftHip = pose[.leftHip], let rightHip = pose[.rightHip] {
                let pill = pillPath(from: viewPoint(for: leftHip, in: size),
                                    to: viewPoint(for: rightHip, in: size),
                                    radius: hipBarRadius)
                context.fill(pill, with: .color(JointColors.hip))
            }
        }
        .allowsHitTesting(false)
    }

    private func boneColor(from: VNHumanBodyPoseObservation.JointName,
                           to: VNHumanBodyPoseObservation.JointName) -> Color {
        if JointColors.color(for: from) != nil || JointColors.color(for: to) != nil {
            return JointColors.color(for: from) ?? JointColors.color(for: to) ?? .green
        }
        return .green.opacity(0.9)
    }

    /// Static target shapes at the bottom-of-squat positions measured from
    /// the reference video and scaled to this athlete: one pill spanning both
    /// hip targets, one circle per shoulder and per knee (the spots to drive
    /// into — each fills when hit), and a tiny dot per shoulder and per
    /// foot marking the standing-level positions.
    private func drawReferenceTargets(_ reference: ReferencePose,
                                      in context: inout GraphicsContext,
                                      size: CGSize) {
        let tolerance = onTargetRadius(in: size)
        guard tolerance > 0 else { return }

        let targetRadius = tolerance * 0.6
        let standingMarkerRadius = targetRadius * 0.5
        let hipBarRadius = targetRadius * 0.35

        drawHipBar(reference, tolerance: tolerance, barRadius: hipBarRadius,
                   color: JointColors.hip, in: &context, size: size)

        for joint in JointColors.shoulderJoints.union(JointColors.kneeJoints) {
            guard let target = reference.targets[joint],
                  let color = JointColors.color(for: joint) else { continue }
            drawTargetCircle(joint: joint, target: target, color: color,
                             radius: targetRadius, tolerance: tolerance,
                             in: &context, size: size)
        }

        for joint in JointColors.shoulderJoints {
            guard phase == .standing,
                  let marker = reference.standingMarkers[joint] else { continue }
            let center = viewPoint(for: marker, in: size)
            let rect = CGRect(x: center.x - standingMarkerRadius, y: center.y - standingMarkerRadius,
                              width: standingMarkerRadius * 2, height: standingMarkerRadius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(JointColors.shoulder.opacity(0.5)))
        }

        for joint: VNHumanBodyPoseObservation.JointName in [.leftAnkle, .rightAnkle] {
            guard let target = reference.targets[joint] else { continue }
            let center = viewPoint(for: target, in: size)
            let rect = CGRect(x: center.x - standingMarkerRadius, y: center.y - standingMarkerRadius,
                              width: standingMarkerRadius * 2, height: standingMarkerRadius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.6)))
        }
    }

    private func drawTargetCircle(joint: VNHumanBodyPoseObservation.JointName,
                                  target: CGPoint,
                                  color: Color,
                                  radius: CGFloat,
                                  tolerance: CGFloat,
                                  in context: inout GraphicsContext,
                                  size: CGSize) {
        let center = viewPoint(for: target, in: size)
        let isOnTarget: Bool
        if let live = pose[joint] {
            let livePoint = viewPoint(for: live, in: size)
            isOnTarget = hypot(livePoint.x - center.x, livePoint.y - center.y) <= tolerance
        } else {
            isOnTarget = false
        }

        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        let circle = Path(ellipseIn: rect)
        if isOnTarget {
            context.fill(circle, with: .color(color.opacity(0.35)))
        }
        context.stroke(circle,
                       with: .color(color),
                       style: StrokeStyle(lineWidth: 6))
    }

    /// One solid pill spanning both hip targets. Outline and fill use the hip color.
    private func drawHipBar(_ reference: ReferencePose,
                            tolerance: CGFloat,
                            barRadius: CGFloat,
                            color: Color,
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

        let pill = pillPath(from: leftPoint, to: rightPoint, radius: barRadius)
        if bothOnTarget {
            context.fill(pill, with: .color(color.opacity(0.35)))
        }
        context.stroke(pill,
                       with: .color(color),
                       style: StrokeStyle(lineWidth: 6))
    }

    private func pillPath(from: CGPoint, to: CGPoint, radius: CGFloat) -> Path {
        let minX = min(from.x, to.x) - radius
        let maxX = max(from.x, to.x) + radius
        let midY = (from.y + to.y) / 2
        let rect = CGRect(x: minX, y: midY - radius,
                          width: maxX - minX, height: radius * 2)
        return Path(roundedRect: rect, cornerRadius: 999)
    }

    private func onTargetRadius(in viewSize: CGSize) -> CGFloat {
        let imageSize = pose.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        return ReferencePose.tolerance * imageSize.height * scale
    }

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
