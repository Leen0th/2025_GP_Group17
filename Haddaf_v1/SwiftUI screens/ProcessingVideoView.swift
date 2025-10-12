//
//  ProcessingVideoView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 09/10/2025.
//

import SwiftUI
import PhotosUI

struct ProcessingVideoView: View {
    @StateObject private var viewModel: VideoProcessingViewModel
    let selectedVideoItem: PhotosPickerItem
    
    init(selectedVideoItem: PhotosPickerItem) {
        self.selectedVideoItem = selectedVideoItem
        _viewModel = StateObject(wrappedValue: VideoProcessingViewModel())
    }

    let accentColor = Color(hex: "#36796C")

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(lineWidth: 12).fill(Color.gray.opacity(0.1))

                    if viewModel.isProcessing {
                        Circle()
                            .trim(from: 0, to: 0.75)
                            .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                            .fill(accentColor)
                            .rotationEffect(Angle(degrees: 360))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: viewModel.isProcessing)
                    }
                    
                    Image("Haddaf_logo").resizable().scaledToFit().frame(width: 80, height: 80)
                }
                .frame(width: 150, height: 150)
                
                Text("Please Wait")
                    .font(.custom("Poppins-Bold", size: 24))
                    .fontWeight(.bold)

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
        .task {
            await viewModel.processVideo(item: selectedVideoItem)
        }
        .navigationDestination(isPresented: $viewModel.processingComplete) {
            PerformanceFeedbackView(viewModel: viewModel)
        }
    }
}
