import SwiftUI
import PhotosUI
import AVKit

// MARK: - Placeholder Tab Screens
struct DiscoveryView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Discovery Page").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}

struct TeamsView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Teams Page").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}

struct ChallengeView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Challenge Page").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}


// MARK: - Video Upload View (Validation Added)
struct VideoUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideoItem: PhotosPickerItem?
    
    // MODIFIED: State to hold the URL for the next view
    @State private var videoURLForNextView: URL?
    
    // MODIFIED: Renamed for clarity
    @State private var navigateToPinpointing = false
    
    // Validation state
    @State private var showDurationAlert = false
    @State private var isCheckingDuration = false

    let accentColor = Color(hex: "#36796C")

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // Header
                    ZStack {
                        Text("Upload Your Video")
                            .font(.custom("Poppins", size: 28))
                            .fontWeight(.medium)
                            .foregroundColor(accentColor)
                        
                        HStack {
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
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
                                .padding(.top, 2) // Aligns icon with first line of text
                            Text("Upload a video of you playing.")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("Ensure you are clearly visible from the start.")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accentColor)
                                .font(.headline)
                                .padding(.top, 2)
                            Text("The maximum video duration is 30 seconds.")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(.secondary)
                        }
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
                                .fill(Color.white)
                                .frame(width: 90, height: 90)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)

                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 50, weight: .medium))
                                .foregroundColor(accentColor.opacity(0.9))
                        }
                        Spacer()
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                            Text("Choose Video")
                                .font(.custom("Poppins", size: 18)).fontWeight(.semibold)
                                .foregroundColor(.white).padding(.horizontal, 40)
                                .padding(.vertical, 12).background(accentColor)
                                .clipShape(Capsule())
                        }
                        .disabled(isCheckingDuration) // Disable while checking
                        Spacer().frame(height: 30)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
                    .background(
                        ZStack {
                            Image("upload_background").resizable().aspectRatio(contentMode: .fill).clipped()
                            Color.white.opacity(0.3)
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
                
                // --- MODIFIED: Loading overlay style ---
                if isCheckingDuration {
                    // Dark background
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .transition(.opacity)
                    
                    // White card
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(accentColor)
                            .scaleEffect(1.5) // Make it a bit larger
                        
                        Text("Checking video duration...")
                            .font(.custom("Poppins", size: 16))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    .padding(30)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                // --- END OF MODIFICATION ---

                // Custom overlay for the duration warning
                if showDurationAlert {
                    DurationWarningOverlay(isPresented: $showDurationAlert, accentColor: accentColor)
                }
            }
            // --- MODIFIED: Animation for the loading overlay ---
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCheckingDuration)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showDurationAlert)
            .onChange(of: selectedVideoItem) { _, newItem in
                // Perform async validation when a video is selected
                guard let item = newItem else { return }
                Task {
                    isCheckingDuration = true
                    defer { isCheckingDuration = false }
                    
                    do {
                        // 1. Get the video's URL
                        guard let transferable = try? await item.loadTransferable(type: VideoPickerTransferable.self) else {
                            print("Failed to load video URL from picker item.")
                            await MainActor.run { selectedVideoItem = nil }
                            return
                        }
                        let videoURL = transferable.videoURL
                        
                        // 2. Load the video asset and get its duration
                        let asset = AVURLAsset(url: videoURL)
                        let duration = try await asset.load(.duration)
                        let durationInSeconds = CMTimeGetSeconds(duration)
                        
                        // 3. Validate the duration
                        if durationInSeconds <= 30.0 {
                            // If valid, proceed to the pinpointing screen
                            self.videoURLForNextView = videoURL
                            navigateToPinpointing = true
                        } else {
                            // If invalid, show the custom alert and reset the picker
                            showDurationAlert = true
                            selectedVideoItem = nil
                        }
                    } catch {
                        print("Error getting video duration: \(error.localizedDescription)")
                        await MainActor.run { selectedVideoItem = nil }
                    }
                }
            }
            // MODIFIED: Pass the binding here
            .navigationDestination(isPresented: $navigateToPinpointing) {
                if let url = videoURLForNextView {
                    // Pass the binding so the child view can dismiss itself
                    PinpointPlayerView(videoURL: url, isPresented: $navigateToPinpointing)
                }
            }
            // ADDED: This modifier is the key
            .onChange(of: navigateToPinpointing) { _, isNavigating in
                // When 'isNavigating' becomes false, it means the user
                // has dismissed PinpointPlayerView by tapping "back".
                // We reset the state so they can pick a new video.
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
                    .font(.title3).fontWeight(.semibold)

                Text("Please select a video that is 30 seconds or shorter.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("OK") {
                    isPresented = false
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(accentColor)
                .cornerRadius(10)
                .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20))
            .frame(width: 320)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
