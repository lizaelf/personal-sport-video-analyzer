# SquatAnalyzer

iOS app that uses the front camera to analyze squat form in real time. It detects body keypoints with Apple's Vision framework, computes joint angles, tracks the squat through its phases, counts reps, and gives plain-language form feedback.

**Pipeline:** Camera → Pose Detection → Angle Analysis → Rule-based Feedback → UI Overlay

## Running the app

1. Open `SquatAnalyzer.xcodeproj` in Xcode.
2. Select your development team under *Signing & Capabilities* (any free Apple ID works).
3. Build and run on a **physical iPhone** (iOS 17+). The simulator has no camera, so the app shows a "camera could not be started" screen there.
4. Prop the phone up, step back until your hips, knees, and feet are in frame, and start squatting.

No video is recorded or uploaded — all processing happens on-device, per frame.

## How it works

| Stage | File | Notes |
|---|---|---|
| Capture | [CameraManager.swift](SquatAnalyzer/Camera/CameraManager.swift) | Front camera via `AVCaptureSession` at 720p; frames rotated to portrait and mirrored to match the preview |
| Pose detection | [PoseDetector.swift](SquatAnalyzer/Pose/PoseDetector.swift) | `VNDetectHumanBodyPoseRequest`; joints below 0.3 confidence are dropped; Vision's bottom-left origin is flipped to screen coordinates |
| Smoothing | [PoseSmoother.swift](SquatAnalyzer/Pose/PoseSmoother.swift) | Exponential smoothing (`prev * 0.7 + current * 0.3`) to reduce jitter; briefly carries missing joints to avoid flicker |
| Angle math | [AngleMath.swift](SquatAnalyzer/Analysis/AngleMath.swift) | Angle at vertex B of A–B–C via the dot product |
| Analysis | [SquatFormAnalyzer.swift](SquatAnalyzer/Analysis/SquatFormAnalyzer.swift) | Phase state machine + form rules + rep counting |
| Orchestration | [SquatSessionViewModel.swift](SquatAnalyzer/SquatSessionViewModel.swift) | Runs detection inline on the camera queue (late frames are discarded, giving natural backpressure), publishes results on the main actor |
| UI | [ContentView.swift](SquatAnalyzer/ContentView.swift), [SkeletonOverlayView.swift](SquatAnalyzer/UI/SkeletonOverlayView.swift) | Live preview, aspect-fill-aligned skeleton overlay, rep/phase/angle HUD, feedback banners |

### Squat phase detection

The knee angle (hip–knee–ankle, averaged over visible sides) drives a state machine:

- **Standing** → knee angle drops below 150° → **Descending**
- **Descending** → below 100° → **Bottom**
- **Bottom** → rises 15° above the deepest point → **Ascending**
- **Ascending** → back above 150° → **Standing** (rep counted, summary feedback shown)

### Feedback rules

Fired at most once per rep while moving, plus a summary at rep completion:

- Knee angle < 70° → *"Knees are too deeply bent"* (error)
- Knee separation < 0.75 × ankle separation → *"Knees are collapsing inward"* (error)
- Hip angle (shoulder–hip–knee) < 50° → *"Leaning too far forward"* (warning)
- Deepest knee angle > 110° at rep end → *"Try to squat deeper"* (warning)
- No issues → *"Good rep!"* (good)

Thresholds live as constants at the top of `SquatFormAnalyzer` for easy tuning.

## Next steps (post-MVP)

- Side-view mode (knee/hip angles are more accurate in profile than head-on)
- Per-rep history and session summary screen
- Calibration of thresholds against the user's baseline mobility
- Left/right symmetry scoring
