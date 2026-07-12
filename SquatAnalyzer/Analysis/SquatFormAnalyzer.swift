import CoreGraphics
import Foundation
import Vision

enum SquatPhase: String {
    case standing = "Standing"
    case descending = "Descending"
    case bottom = "Bottom"
    case ascending = "Ascending"
}

struct Feedback: Identifiable, Equatable {
    enum Severity {
        case good, warning, error
    }

    let id = UUID()
    let message: String
    let severity: Severity
}

/// Per-frame analysis output consumed by the view model.
struct AnalysisResult {
    var phase: SquatPhase
    var kneeAngle: Double?
    var torsoLean: Double?
    var repCount: Int
    var newFeedback: Feedback?
    var viewMode: SquatViewMode
    var isBodyVisible: Bool
}

/// Tracks the squat through its phases using the knee angle and evaluates
/// form rules for both front-facing and side-profile camera setups.
struct SquatFormAnalyzer {

    /// Thresholds differ per camera angle: the front view sees a 2D projection
    /// of the knee angle (a parallel squat reads ~105–125°, calibrated against
    /// reference footage), while the side view sees close to the true angle
    /// (~80–100° at the bottom).
    private struct Tuning {
        var standingThreshold: Double
        var bottomThreshold: Double
        /// Rise from the deepest point that counts as the start of the ascent.
        var ascentHysteresis: Double
        var overFlexionAngle: Double
        var insufficientDepthAngle: Double
        /// Knee angle below which the valgus / knee-forward rules apply.
        var ruleMaxKneeAngle: Double

        static let front = Tuning(standingThreshold: 155,
                                  bottomThreshold: 130,
                                  ascentHysteresis: 12,
                                  overFlexionAngle: 85,
                                  insufficientDepthAngle: 130,
                                  ruleMaxKneeAngle: 130)

        static let side = Tuning(standingThreshold: 150,
                                 bottomThreshold: 100,
                                 ascentHysteresis: 15,
                                 overFlexionAngle: 70,
                                 insufficientDepthAngle: 110,
                                 ruleMaxKneeAngle: 120)
    }

    // Form rule thresholds shared across views.
    private let kneeValgusRatio = 0.8
    /// Side view: torso tilt from vertical (degrees). Good squats are often 30–50° at the bottom.
    private let excessiveTorsoLeanAngle = 58.0
    /// Side view: knee horizontal offset relative to shin length.
    private let excessiveKneeForwardRatio = 0.42

    /// User's Авто / Спереду / Збоку choice. Changing it mid-rep restarts the
    /// phase tracking (the two views' thresholds aren't comparable) but keeps reps.
    var modeSelection: ViewModeSelection = .auto {
        didSet {
            guard modeSelection != oldValue else { return }
            phase = .standing
            previousKneeAngle = nil
            minKneeAngleInRep = 180
            issuesThisRep.removeAll()
            frontModeFrames = 0
            sideModeFrames = 0
        }
    }

    private(set) var phase: SquatPhase = .standing
    private(set) var repCount = 0
    private(set) var viewMode: SquatViewMode = .front

    private var previousKneeAngle: Double?
    private var minKneeAngleInRep = 180.0
    private var issuesThisRep: Set<String> = []
    private var stableViewMode: SquatViewMode = .front
    private var frontModeFrames = 0
    private var sideModeFrames = 0

    private var tuning: Tuning {
        if case .front = viewMode { .front } else { .side }
    }

    mutating func analyze(_ pose: DetectedPose) -> AnalysisResult {
        switch modeSelection {
        case .auto:
            updateStableViewMode(PoseOrientation.detect(in: pose))
        case .front:
            stableViewMode = .front
        case .side:
            stableViewMode = PoseOrientation.detectSide(in: pose)
        }
        viewMode = stableViewMode

        let bodyVisible = PoseOrientation.isBodyVisible(in: pose, mode: viewMode)
        let torsoLean = torsoLean(of: pose, mode: viewMode)
        guard let kneeAngle = kneeAngle(of: pose, mode: viewMode) else {
            return AnalysisResult(phase: phase,
                                  kneeAngle: nil,
                                  torsoLean: torsoLean,
                                  repCount: repCount,
                                  newFeedback: nil,
                                  viewMode: viewMode,
                                  isBodyVisible: bodyVisible)
        }

        var feedback: Feedback?
        let previous = previousKneeAngle ?? kneeAngle
        previousKneeAngle = kneeAngle

        switch phase {
        case .standing:
            if kneeAngle < tuning.standingThreshold, kneeAngle < previous {
                phase = .descending
                minKneeAngleInRep = kneeAngle
                issuesThisRep.removeAll()
            }

        case .descending:
            minKneeAngleInRep = min(minKneeAngleInRep, kneeAngle)
            if kneeAngle < tuning.bottomThreshold {
                phase = .bottom
            } else if kneeAngle > tuning.standingThreshold {
                phase = .standing // Aborted the descent without a real squat.
            }
            feedback = movementFeedback(pose: pose,
                                        kneeAngle: kneeAngle,
                                        torsoLean: torsoLean,
                                        mode: viewMode)

        case .bottom:
            minKneeAngleInRep = min(minKneeAngleInRep, kneeAngle)
            if kneeAngle > minKneeAngleInRep + tuning.ascentHysteresis {
                phase = .ascending
            }
            feedback = movementFeedback(pose: pose,
                                        kneeAngle: kneeAngle,
                                        torsoLean: torsoLean,
                                        mode: viewMode)

        case .ascending:
            minKneeAngleInRep = min(minKneeAngleInRep, kneeAngle)
            if kneeAngle > tuning.standingThreshold {
                phase = .standing
                repCount += 1
                feedback = repSummary()
            } else {
                feedback = movementFeedback(pose: pose,
                                            kneeAngle: kneeAngle,
                                            torsoLean: torsoLean,
                                            mode: viewMode)
            }
        }

        return AnalysisResult(phase: phase,
                              kneeAngle: kneeAngle,
                              torsoLean: torsoLean,
                              repCount: repCount,
                              newFeedback: feedback,
                              viewMode: viewMode,
                              isBodyVisible: bodyVisible)
    }

    mutating func reset() {
        phase = .standing
        repCount = 0
        previousKneeAngle = nil
        minKneeAngleInRep = 180
        issuesThisRep.removeAll()
        stableViewMode = .front
        frontModeFrames = 0
        sideModeFrames = 0
        viewMode = .front
    }

    // MARK: - View mode

    private mutating func updateStableViewMode(_ detected: SquatViewMode) {
        switch detected {
        case .front:
            frontModeFrames += 1
            sideModeFrames = 0
            if frontModeFrames >= 8 {
                stableViewMode = .front
            }
        case .side(let side):
            sideModeFrames += 1
            frontModeFrames = 0
            if sideModeFrames >= 8 {
                stableViewMode = .side(side)
            }
        }
    }

    // MARK: - Form rules

    /// Rules checked continuously while the user is in motion.
    /// Each fires at most once per rep so feedback doesn't spam.
    private mutating func movementFeedback(pose: DetectedPose,
                                           kneeAngle: Double,
                                           torsoLean: Double?,
                                           mode: SquatViewMode) -> Feedback? {
        if kneeAngle < tuning.overFlexionAngle, issuesThisRep.insert("depth").inserted {
            return Feedback(message: "Коліна занадто глибоко зігнуті. Зменши глибину або контролюй рух.",
                            severity: .error)
        }

        switch mode {
        case .front:
            if let ratio = kneeSeparationRatio(of: pose),
               ratio < kneeValgusRatio,
               kneeAngle < tuning.ruleMaxKneeAngle,
               issuesThisRep.insert("valgus").inserted {
                return Feedback(message: "Коліна завалюються всередину. Розводь їх назовні.",
                                severity: .error)
            }
        case .side(let side):
            if let ratio = kneeForwardRatio(of: pose, side: side),
               ratio > excessiveKneeForwardRatio,
               kneeAngle < tuning.ruleMaxKneeAngle,
               issuesThisRep.insert("kneeForward").inserted {
                return Feedback(message: "Коліно занадто далеко вперед. Сідай трохи назад і тримай вагу на п'ятках.",
                                severity: .warning)
            }
        }

        // Torso lean is only meaningful in side view — from the front, shoulder/hip x-offset
        // does not reflect forward lean and the old shoulder–hip–knee angle misfired constantly.
        if case .side = mode,
           let lean = torsoLean,
           lean > excessiveTorsoLeanAngle,
           kneeAngle < tuning.ruleMaxKneeAngle,
           issuesThisRep.insert("lean").inserted {
            return Feedback(message: "Занадто нахиляєшся вперед. Тримай груди піднято.",
                            severity: .warning)
        }

        return nil
    }

    /// Summary shown when a rep completes (back to standing).
    private mutating func repSummary() -> Feedback? {
        if minKneeAngleInRep > tuning.insufficientDepthAngle, issuesThisRep.isEmpty {
            return Feedback(message: "Присідай глибше — намагайся, щоб стегна були паралельні підлозі.",
                            severity: .warning)
        }
        if issuesThisRep.isEmpty {
            return Feedback(message: "Гарний повтор! Глибина і контроль на рівні.", severity: .good)
        }
        return nil
    }

    // MARK: - Metrics

    /// Knee angle (hip–knee–ankle). In side view only the visible leg is used.
    private func kneeAngle(of pose: DetectedPose, mode: SquatViewMode) -> Double? {
        switch mode {
        case .front:
            let sides: [BodySide] = [.left, .right]
            let angles = sides.compactMap { angle(forLegOf: $0, in: pose) }
            guard !angles.isEmpty else { return nil }
            return angles.reduce(0, +) / Double(angles.count)
        case .side(let side):
            return angle(forLegOf: side, in: pose)
        }
    }

    /// Torso tilt from vertical using the visible shoulder and hip. Side view only.
    private func torsoLean(of pose: DetectedPose, mode: SquatViewMode) -> Double? {
        guard case .side(let side) = mode else { return nil }

        let shoulder: VNHumanBodyPoseObservation.JointName = side == .left ? .leftShoulder : .rightShoulder
        let hip: VNHumanBodyPoseObservation.JointName = side == .left ? .leftHip : .rightHip
        guard let s = pose[shoulder], let h = pose[hip] else { return nil }

        return AngleMath.leanFromVertical(shoulder: s, hip: h)
    }

    private func angle(forLegOf side: BodySide, in pose: DetectedPose) -> Double? {
        let (hip, knee, ankle) = PoseOrientation.legChain(for: side)
        guard let h = pose[hip], let k = pose[knee], let a = pose[ankle] else { return nil }
        return AngleMath.angle(h, vertex: k, a)
    }

    /// Knee separation relative to ankle separation. Front view only.
    private func kneeSeparationRatio(of pose: DetectedPose) -> Double? {
        guard
            let leftKnee = pose[.leftKnee], let rightKnee = pose[.rightKnee],
            let leftAnkle = pose[.leftAnkle], let rightAnkle = pose[.rightAnkle]
        else { return nil }

        let ankleSeparation = AngleMath.distance(leftAnkle, rightAnkle)
        guard ankleSeparation > 0.01 else { return nil }
        return AngleMath.distance(leftKnee, rightKnee) / ankleSeparation
    }

    /// Side view: how far the knee sits in front of the ankle relative to leg length.
    private func kneeForwardRatio(of pose: DetectedPose, side: BodySide) -> Double? {
        let (hip, knee, ankle) = PoseOrientation.legChain(for: side)
        guard let h = pose[hip], let k = pose[knee], let a = pose[ankle] else { return nil }

        let legLength = AngleMath.distance(h, a)
        guard legLength > 0.02 else { return nil }

        return abs(k.x - a.x) / legLength
    }
}
