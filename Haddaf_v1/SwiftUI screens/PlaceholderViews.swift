import SwiftUI
import PhotosUI
import AVKit

// MARK: - Placeholder Tab Screens
struct TeamsView: View {
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Teams Page")
                    .font(.system(size: 32, design: .rounded))
                    .foregroundColor(.secondary)
                
                Text("To be developed in upcoming sprints")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
    }
}

/*struct ChallengeView: View {
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Challenge Page")
                    .font(.system(size: 32, design: .rounded))
                    .foregroundColor(.secondary)
                
                Text("To be developed in upcoming sprints")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
    }
}
*/
struct LineupBuilderView: View {
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Lineup Builder Page")
                    .font(.system(size: 32, design: .rounded))
                    .foregroundColor(.secondary)
                
                Text("To be developed in upcoming sprints")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
    }
}


// MARK: - Video Upload View (Validation Added)
struct VideoUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideoItem: PhotosPickerItem?
    
    @State private var videoURLForNextView: URL?
    @State private var navigateToPinpointing = false
    
    @State private var showDurationAlert = false
    @State private var isCheckingDuration = false

    let accentColor = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ZStack {
                        Text("Upload Your Video")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(accentColor)
                        
                        HStack {
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    // MODIFIED: Use new color
                                    .background(BrandColors.lightGray.opacity(0.7))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    
                    // --- Timeline ---
                    MultiStepProgressBar(currentStep: .upload)
                        .padding(.bottom, 30)
                    
                    // --- GUIDELINES ---
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Upload a video of yourself playing football.")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Ensure you are clearly visible from the start.")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("The maximum video duration is 30 seconds.")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        // --- DISCLAIMER ---
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Upload videos that include you as a player. Do not upload someone else’s videos.")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("When selecting a player in the video, make sure to pinpoint yourself not another person.")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)

                    Spacer()

                    // Main upload area
                    VStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(BrandColors.background)
                                .frame(width: 90, height: 90)
                                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 50, weight: .medium))
                                .foregroundColor(accentColor.opacity(0.9))
                        }
                        Spacer()
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                            Text("Choose Video")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white).padding(.horizontal, 40)
                                .padding(.vertical, 12).background(accentColor)
                                .clipShape(Capsule())
                                .shadow(color: accentColor.opacity(0.3), radius: 10, y: 5)
                        }
                        .disabled(isCheckingDuration)
                        Spacer().frame(height: 30)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
                    .background(
                        ZStack {
                            Image("upload_background").resizable().aspectRatio(contentMode: .fill).clipped()
                            BrandColors.background.opacity(0.3)
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .foregroundColor(accentColor.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(accentColor, lineWidth: 3)
                    )
                    .cornerRadius(20)
                    .padding(.horizontal)

                    Spacer()
                    Spacer()
                }
                
                if isCheckingDuration {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .transition(.opacity)
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(accentColor)
                            .scaleEffect(1.5)
                        
                        Text("Checking video duration...")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(30)
                    .background(BrandColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if showDurationAlert {
                    DurationWarningOverlay(isPresented: $showDurationAlert, accentColor: accentColor)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCheckingDuration)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showDurationAlert)
            .onChange(of: selectedVideoItem) { _, newItem in
                // 1: Make sure a video was actually selected
                guard let item = newItem else { return }
                Task {
                    // 2: Show loading while checking the video duration
                    isCheckingDuration = true
                    defer { isCheckingDuration = false }
                    do {
                        // 3: Load transferable object to extract the video URL
                        guard let transferable = try? await item.loadTransferable(type: VideoPickerTransferable.self) else {
                            print("Failed to load video URL from picker item.")
                            await MainActor.run { selectedVideoItem = nil }
                            return
                        }
                        // 4: Get the video file URL
                        let videoURL = transferable.videoURL
                        // 5: Create an AVAsset to read metadata
                        let asset = AVURLAsset(url: videoURL)
                        // 6: Load the duration from the asset
                        let duration = try await asset.load(.duration)
                        // 7: Convert the duration to seconds
                        let durationInSeconds = CMTimeGetSeconds(duration)
                        // 8: Check that the video does not exceed 30 seconds
                        if durationInSeconds <= 30.0 {
                            // 9: Save the URL and navigate to the next screen
                            self.videoURLForNextView = videoURL
                            navigateToPinpointing = true
                        } else {
                            showDurationAlert = true
                            selectedVideoItem = nil
                        }
                    } catch {
                        print("Error getting video duration: \(error.localizedDescription)")
                        await MainActor.run { selectedVideoItem = nil }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToPinpointing) {
                if let url = videoURLForNextView {
                    PinpointPlayerView(videoURL: url, isPresented: $navigateToPinpointing)
                }
            }
            .onChange(of: navigateToPinpointing) { _, isNavigating in
                if !isNavigating {
                    selectedVideoItem = nil
                    videoURLForNextView = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cancelUploadFlow)) { _ in
                dismiss()
            }
        }
    }
}

// MARK: - Custom Warning Overlay View
private struct DurationWarningOverlay: View {
    @Binding var isPresented: Bool
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 20) {
                Text("Video Too Long")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                Text("Please select a video that is 30 seconds or shorter.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("OK") {
                    isPresented = false
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(accentColor)
                .cornerRadius(12)
                .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20))
            .frame(width: 320)
            .background(BrandColors.background)
            .cornerRadius(20)
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
