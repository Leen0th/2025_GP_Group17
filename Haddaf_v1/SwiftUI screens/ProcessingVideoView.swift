//
//  ProcessingVideoView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 09/10/2025.
//

import SwiftUI
import PhotosUI

struct ProcessingVideoView: View {
    let selectedVideoItem: PhotosPickerItem

    @State private var isAnimating = false
    @State private var isProcessingComplete = false
    
    let accentColor = Color(hex: "#36796C")

    var body: some View {
        // ✅ FIX: Use a ZStack as the main container to lock the content in the center.
        ZStack {
            // The VStack no longer needs Spacers because the ZStack handles centering.
            VStack(spacing: 20) {
                // Animated Spinner and Logo
                ZStack {
                    Circle()
                        .stroke(lineWidth: 12)
                        .fill(Color.gray.opacity(0.1))

                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .fill(accentColor)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    
                    Image("Haddaf_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                }
                .frame(width: 150, height: 150)
                
                // Text below the spinner
                Text("Please Wait")
                    .font(.custom("Poppins-Bold", size: 24))
                    .fontWeight(.bold)

                Text("It may take a few minutes to process this video")
                    .font(.custom("Poppins-Regular", size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea() // This prevents the nav bar from affecting the layout
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                isProcessingComplete = true
            }
        }
        .navigationDestination(isPresented: $isProcessingComplete) {
            PerformanceFeedbackView()
        }
    }
}
