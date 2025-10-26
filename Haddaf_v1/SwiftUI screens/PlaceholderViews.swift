import SwiftUI
import PhotosUI
import AVKit

// MARK: - Placeholder Tab Screens
struct DiscoveryView: View {
    var body: some View {
        ZStack {
            // MODIFIED: Use new background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            Text("Discovery Page")
                // MODIFIED: Use new font
                .font(.system(size: 32, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

struct TeamsView: View {
    var body: some View {
        ZStack {
            // MODIFIED: Use new background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            Text("Teams Page")
                // MODIFIED: Use new font
                .font(.system(size: 32, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

struct ChallengeView: View {
    var body: some View {
        ZStack {
            // MODIFIED: Use new background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            Text("Challenge Page")
                // MODIFIED: Use new font
                .font(.system(size: 32, design: .rounded))
                .foregroundColor(.secondary)
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

    // MODIFIED: Use new BrandColors
    let accentColor = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                // MODIFIED: Use new background
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    ZStack {
                        Text("Upload Your Video")
                            // MODIFIED: Use new font
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
                    .padding(.bottom, 50)

                    // --- ADDED GUIDELINES ---
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Upload a video of you playing.")
                                // MODIFIED: Use new font
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Ensure you are clearly visible from the start.")
                                // MODIFIED: Use new font
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("The maximum video duration is 30 seconds.")
                                // MODIFIED: Use new font
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        // --- ADDED DISCLAIMER ---
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Upload and pinpoint only videos that feature you personally. Using someone else's video or identity is strictly prohibited.")
                                // MODIFIED: Use new font
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        // --- END ADDED DISCLAIMER ---
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)
                    // --- END ADDED GUIDELINES ---

                    Spacer()

                    // Main upload area
                    VStack {
                        Spacer()
                        ZStack {
                            Circle()
                                // MODIFIED: Use new background
                                .fill(BrandColors.background)
                                .frame(width: 90, height: 90)
                                // MODIFIED: Use new shadow
                                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 50, weight: .medium))
                                .foregroundColor(accentColor.opacity(0.9))
                        }
                        Spacer()
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                            Text("Choose Video")
                                // MODIFIED: Use new font
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white).padding(.horizontal, 40)
                                .padding(.vertical, 12).background(accentColor)
                                .clipShape(Capsule())
                                // MODIFIED: Add shadow
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
                            // MODIFIED: Use new background
                            BrandColors.background.opacity(0.3)
                        }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .foregroundColor(accentColor.opacity(0.4))
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
                            // MODIFIED: Use new font
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(30)
                    // MODIFIED: Use new background
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
                // ... (your original onChange logic is unchanged) ...
                guard let item = newItem else { return }
                Task {
                    isCheckingDuration = true
                    defer { isCheckingDuration = false }
                    do {
                        guard let transferable = try? await item.loadTransferable(type: VideoPickerTransferable.self) else {
                            print("Failed to load video URL from picker item.")
                            await MainActor.run { selectedVideoItem = nil }
                            return
                        }
                        let videoURL = transferable.videoURL
                        let asset = AVURLAsset(url: videoURL)
                        let duration = try await asset.load(.duration)
                        let durationInSeconds = CMTimeGetSeconds(duration)
                        if durationInSeconds <= 30.0 {
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
                    // MODIFIED: Use new font
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                Text("Please select a video that is 30 seconds or shorter.")
                    // MODIFIED: Use new font
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("OK") {
                    isPresented = false
                }
                // MODIFIED: Use new font
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(accentColor)
                .cornerRadius(12) // MODIFIED
                .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20))
            .frame(width: 320)
            // MODIFIED: Use new background
            .background(BrandColors.background)
            .cornerRadius(20)
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
