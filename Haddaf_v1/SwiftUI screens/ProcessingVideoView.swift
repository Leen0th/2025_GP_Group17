import SwiftUI
import AVKit
import PhotosUI

struct ProcessingVideoView: View {
    @StateObject private var viewModel: VideoProcessingViewModel
    @Environment(\.dismiss) private var dismiss

    let selectedVideoItem: PhotosPickerItem

    init(selectedVideoItem: PhotosPickerItem) {
        self.selectedVideoItem = selectedVideoItem
        _viewModel = StateObject(wrappedValue: VideoProcessingViewModel())
    }

    let accentColor = Color(hex: "#36796C")
    @State private var navigateToFeedback = false
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .task { await viewModel.processVideo(item: selectedVideoItem) }
        .onAppear { isAnimating = true }
        .onChange(of: viewModel.processingComplete) { _, v in
            if v { navigateToFeedback = true }
        }
        .navigationDestination(isPresented: $navigateToFeedback) {
            PerformanceFeedbackView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .postCreated)) { _ in
            // Close processing screen after successful Post
            dismiss()
        }
    }
}
