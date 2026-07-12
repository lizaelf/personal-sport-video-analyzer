import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SquatSessionViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.cameraState {
            case .running:
                sessionView
            case .starting:
                ProgressView("Starting camera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .permissionDenied:
                CameraUnavailableView(
                    message: "Camera access is required to analyze your squats. Enable it in Settings → Privacy → Camera.",
                    showsSettingsButton: true
                )
            case .failed:
                CameraUnavailableView(
                    message: "The camera didn't start. This is expected in the iOS Simulator (no camera) and can happen in \"Designed for iPad\" mode on a Mac. Run SquatAnalyzer on a physical iPhone to record and analyze your squats.",
                    showsSettingsButton: false
                )
            }
        }
        .task { await viewModel.startSession() }
        // Drive the capture session off the scene phase. iOS terminates apps
        // (SIGTERM) that keep an AVCaptureSession running while backgrounded, so
        // the session MUST be stopped on background and resumed on foreground.
        // .onDisappear alone is not enough — it doesn't fire when the app is
        // backgrounded while this view is still on screen.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.resumeSession()
            case .background, .inactive:
                viewModel.stopSession()
            @unknown default:
                break
            }
        }
    }

    private var sessionView: some View {
        ZStack {
            cameraPreview

            if let pose = viewModel.frame.pose {
                SkeletonOverlayView(pose: pose)
                    .ignoresSafeArea()
            }

            VStack {
                statusBar
                Spacer()
                if !viewModel.isReceivingFrames {
                    WaitingForCameraView()
                } else if !viewModel.frame.isBodyVisible {
                    PositioningHintView()
                }
                Spacer()
                if let feedback = viewModel.feedback {
                    FeedbackBanner(feedback: feedback)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                formReadout
            }
            .padding()
            .animation(.spring(duration: 0.3), value: viewModel.feedback)
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            CameraFramePreviewView(camera: viewModel.camera)
                .ignoresSafeArea()
        } else {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()
        }
    }

    private var statusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("REPS")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(viewModel.frame.repCount)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            Spacer()

            Text(viewModel.frame.phase.rawValue)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                viewModel.resetSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var formReadout: some View {
        HStack(spacing: 10) {
            readoutCapsule(title: "Коліно", value: viewModel.frame.kneeAngle.map { "\(Int($0))°" } ?? "—")
        }
    }

    private func readoutCapsule(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct FeedbackBanner: View {
    let feedback: Feedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3.bold())
            Text(feedback.message)
                .font(.callout.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 8)
    }

    private var color: Color {
        switch feedback.severity {
        case .good: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var icon: String {
        switch feedback.severity {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

/// Shown when the capture session is running but no frames have arrived yet.
/// On a device this flashes briefly at startup; in the iOS Simulator it stays,
/// because the simulator does not provide a live camera feed.
struct WaitingForCameraView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("Waiting for the camera…")
                .font(.callout.bold())
            Text("The iOS Simulator has no live camera. Run on a physical iPhone to see yourself and get form analysis.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
    }
}

struct PositioningHintView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.largeTitle)
            Text("Відійди назад так, щоб стегна, коліна і стопи були в кадрі")
                .font(.callout.bold())
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CameraUnavailableView: View {
    let message: String
    let showsSettingsButton: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text(message)
                .font(.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if showsSettingsButton {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
    }
}

#Preview {
    ContentView()
}
