import SwiftUI
import AVKit
import PhotosUI

struct ProcessingVideoView: View {
    @StateObject private var viewModel: VideoProcessingViewModel
    @Environment(\.dismiss) private var dismiss

    // MODIFIED: Update the inputs for this view
    let videoURL: URL
    let pinpoint: CGPoint

    // MODIFIED: Update the initializer
    init(videoURL: URL, pinpoint: CGPoint) {
        self.videoURL = videoURL
        self.pinpoint = pinpoint
        _viewModel = StateObject(wrappedValue: VideoProcessingViewModel())
    }

    // MODIFIED: Use new BrandColors
    let accentColor = BrandColors.darkTeal
    
    @State private var navigateToFeedback = false
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // MODIFIED: Use new background
            BrandColors.gradientBackground.ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    // MODIFIED: Use new color
                    Circle().stroke(lineWidth: 12).fill(BrandColors.lightGray)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .fill(accentColor)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                    Image("Haddaf_logo").resizable().scaledToFit().frame(width: 80, height: 80)
                }
                .frame(width: 150, height: 150)
                
                Text("Please Wait")
                    // MODIFIED: Use new font
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                Text(viewModel.processingStateMessage)
                    // MODIFIED: Use new font
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: accentColor))
                    .padding(.horizontal, 50)
                    .animation(.linear, value: viewModel.progress)
                
                Text(String(format: "%.0f%%", viewModel.progress * 100))
                    // MODIFIED: Use new font
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(accentColor)
                    .animation(nil, value: viewModel.progress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .task { await viewModel.processVideo(url: videoURL, pinpoint: pinpoint) }
        .onAppear { isAnimating = true }
        .onChange(of: viewModel.processingComplete) { _, v in
            if v { navigateToFeedback = true }
        }
        .navigationDestination(isPresented: $navigateToFeedback) {
            PerformanceFeedbackView(viewModel: viewModel)
        }
    }
}
