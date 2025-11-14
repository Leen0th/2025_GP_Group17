import SwiftUI
import AVKit
import PhotosUI
struct ProcessingVideoView: View {
    // Holds a single ViewModel instance so it survives view redraws.
    @StateObject private var viewModel: VideoProcessingViewModel
    @Environment(\.dismiss) private var dismiss
    let videoURL: URL
    let pinpoint: CGPoint
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    init(videoURL: URL, pinpoint: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat) {
        self.videoURL = videoURL
        self.pinpoint = pinpoint
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        _viewModel = StateObject(wrappedValue: VideoProcessingViewModel())
    }
    private let accentColor = BrandColors.darkTeal
    @State private var navigateToFeedback = false
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(BrandColors.lightGray, lineWidth: 12)
                    if viewModel.isProcessing && !viewModel.showingAnalysisFailure {
                        SpinningArc(
                            color: accentColor,
                            lineWidth: 10,
                            trimEnd: 0.75
                        )
                    }
                    Image("Haddaf_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                }
                .frame(width: 150, height: 150)
                Text("Please Wait")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                // Shows dynamic processing messages like uploading or analyzing.
                Text(viewModel.processingStateMessage)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                ProgressView(value: viewModel.progress)
                    .tint(accentColor)
                    .padding(.horizontal, 50)
                    .opacity(viewModel.isProcessing || viewModel.progress > 0.0 ? 1 : 0)
                    .animation(.linear, value: viewModel.progress)
                Text(String(format: "%.0f%%", viewModel.progress * 100))
                    .font(.system(size: 20, design: .rounded))
                    .foregroundColor(accentColor)
                    .animation(nil, value: viewModel.progress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        // Runs once on appear to start video processing with URL, pinpoint, and frame size.
        .task {
            await viewModel.processVideo(
                url: videoURL,
                pinpoint: pinpoint,
                frameWidth: frameWidth,
                frameHeight: frameHeight
            )
        }
        // When processingComplete becomes true, trigger navigation to the Feedback screen.

        .onChange(of: viewModel.processingComplete) { _, done in
            if done { navigateToFeedback = true }
        }
        .navigationDestination(isPresented: $navigateToFeedback) {
            PerformanceFeedbackView(viewModel: viewModel)
        }
        .alert("Analysis Failed", isPresented: $viewModel.showingAnalysisFailure) {
            Button("Retry", role: .none) {
                Task { await viewModel.retryAnalysis() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.resetAfterPosting()
                dismiss()
            }
        } message: {
            Text("Analysis failed. Please ensure you have a stable connection and try again.")
        }
    }
}
private struct SpinningArc: View {
    let color: Color
    let lineWidth: CGFloat
    let trimEnd: CGFloat
    @State private var rotation: Double = 0
    var body: some View {
        Circle()
            .trim(from: 0, to: trimEnd)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .foregroundColor(color)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                rotation = 0
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            .onDisappear {
                rotation = 0
            }
            .accessibilityHidden(true)
    }
}
