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

    let accentColor = Color(hex: "#36796C")
    @State private var navigateToFeedback = false
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                // This is your existing spinner, leave it as-is
                ZStack {
                    Circle().stroke(lineWidth: 12).fill(Color.gray.opacity(0.1))
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .fill(accentColor)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                    Image("Haddaf_logo").resizable().scaledToFit().frame(width: 80, height: 80)
                }
                .frame(width: 150, height: 150)
                
                Text("Please Wait").font(.custom("Poppins-Bold", size: 24)).fontWeight(.bold)
                
                Text(viewModel.processingStateMessage)
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                // --- ADD THESE LINES ---
                
                // 1. The Progress Bar
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: accentColor))
                    .padding(.horizontal, 50)
                    .animation(.linear, value: viewModel.progress) // Animate progress changes
                
                // 2. The Percentage Text
                Text(String(format: "%.0f%%", viewModel.progress * 100))
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(accentColor)
                    .animation(nil, value: viewModel.progress) // Don't animate the text itself
                
                // --- END OF ADDED LINES ---
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        // MODIFIED: Call the updated processing function in the viewModel
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
