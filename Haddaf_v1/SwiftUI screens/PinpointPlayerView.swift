import SwiftUI
import AVKit
import Combine

// MARK: - Player View Model
@MainActor // because it publishes properties that are bound to the UI, ensuring all updates happen on the main thread.
class PlayerViewModel: NSObject, ObservableObject {
    // The underlying `AVPlayer` instance.
    @Published var player: AVPlayer
    // `true` if the player is currently playing; `false` otherwise.
    @Published var isPlaying = false
    // The total duration of the video in seconds.
    @Published var duration: TimeInterval = 0.0
    // The current playback time of the video in seconds.
    @Published var currentTime: TimeInterval = 0.0
    
    // An observer token for the player's periodic time updates. Stored for later removal
    private var timeObserver: Any?

    // Initializes the view model with a video URL of the video to be played.
    init(videoURL: URL) {
        self.player = AVPlayer(url: videoURL)
        super.init()
        setupPlayer()
    }

    // Cleans up all observers and pauses the player to prevent memory leaks and background audio.
    func cleanup() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        // Remove Key-Value Observer
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        player.pause()
    }

    // Sets up the necessary observers for the player
    private func setupPlayer() {
        // Asynchronously load the video's duration
        Task {
            if let duration = try? await player.currentItem?.asset.load(.duration) {
                self.duration = duration.seconds
            }
        }

        // Observer to update `currentTime` for the UI
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        // Key-Value Observer to monitor the player's actual playback status
        // This is more reliable than a simple boolean for checking play/pause state
        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
    }

    // The Key-Value Observer handler for observing changes to player properties
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus" {
            // Update the `isPlaying` published property based on the player's status
            self.isPlaying = self.player.timeControlStatus == .playing
        }
    }

    // Toggles the player between playing and paused states
    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    // Seeks the player to a specific time interval.
    func seek(to time: TimeInterval) {
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

// Formats a `TimeInterval` (in seconds) into a "00:00" string format
fileprivate struct TimeLabel: View {
    // The time interval to display in seconds
    let time: TimeInterval
    private static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.zeroFormattingBehavior = .pad
        return f
    }()
    var body: some View {
        Text(Self.formatter.string(from: time) ?? "00:00")
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundColor(.secondary)
    }
}

// MARK: - Main View
struct PinpointPlayerView: View {
    // The local URL of the video to be analyzed
    let videoURL: URL
    // A binding to control the presentation/dismissal of this view
    @Binding var isPresented: Bool
    // The view model that manages the `AVPlayer` state
    @StateObject private var viewModel: PlayerViewModel
    
    // MARK: - UI State
    // `true` when the user has confirmed a frame and is ready to pinpoint; `false` if they are still scrubbing.
    @State private var isFrameConfirmed = false
    // Stores the `CGPoint` where the user tapped on the video frame
    @State private var selectedPoint: CGPoint?
    // `true` to trigger navigation to the `ProcessingVideoView`.
    @State private var navigateToProcessing = false
    // The natural width of the video, loaded asynchronously
    @State private var frameWidth: CGFloat = 1920
    // The natural height of the video, loaded asynchronously
    @State private var frameHeight: CGFloat = 1080
    // The current step in the upload process
    @State private var step: UploadStep = .selectScene
    
    private let accentColor = BrandColors.darkTeal
    
    // Initializer to create the `StateObject` with the `videoURL` parameter
    init(videoURL: URL, isPresented: Binding<Bool>) {
        self.videoURL = videoURL
        self._isPresented = isPresented
        _viewModel = StateObject(wrappedValue: PlayerViewModel(videoURL: videoURL))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar showing "Upload" (complete) and "Scene" (current)
                MultiStepProgressBar(currentStep: step)
                    .padding(.top, 20)
                
                // Instructions text that changes based on the current step
                instructionsView
                
                // The video player view with the tap-to-pinpoint overlay
                videoPlayerWithOverlay
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                    .padding(.horizontal)
                
                // Show controls (slider, play/pause) only during step 1
                if !isFrameConfirmed {
                    customControlsView
                        .padding(.horizontal)
                        .transition(.opacity)
                }
                
                Spacer()
                // "Back" / "Continue" buttons that change based on the step
                footerButtons
            }
            .background(BrandColors.backgroundGradientEnd.ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            .onAppear {
                // When the view appears, asynchronously load the video's natural dimensions
                Task {
                    do {
                        let asset = AVAsset(url: videoURL)
                        if let track = try await asset.loadTracks(withMediaType: .video).first {
                            let size = try await track.load(.naturalSize)
                            frameWidth = size.width
                            frameHeight = size.height
                            print("Video dimensions: \(frameWidth)x\(frameHeight)")
                        }
                    } catch {
                        print("⚠️ Error loading video dimensions: \(error)")
                    }
                }
            }
            // Clean up the player and its observers to prevent memory leaks
            .onDisappear { viewModel.cleanup() }
            .navigationDestination(isPresented: $navigateToProcessing) {
                // Navigate to the processing view, passing all necessary data
                if let point = selectedPoint {
                    ProcessingVideoView(videoURL: videoURL, pinpoint: point, frameWidth: frameWidth, frameHeight: frameHeight)
                }
            }
        }
    }
    
    // MARK: - Subviews
    // A view that displays instructions to the user, changing based on the current step
    private var instructionsView: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(isFrameConfirmed
                ? "Tap on yourself in the video to mark your position clearly. Then click Continue to proceed."
                : "Use the timeline below to find a scene where you are fully visible. Then click Continue to proceed.")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .animation(.easeInOut, value: isFrameConfirmed)
    }
    
    private var videoPlayerWithOverlay: some View {
        ZStack {
            VideoPlayer(player: viewModel.player)
                .disabled(true)
                .aspectRatio(9/16, contentMode: .fit)
                .allowsHitTesting(false)
            
            // If the frame is confirmed, add the tap-to-pinpoint overlay
            if isFrameConfirmed {
                GeometryReader { geometry in
                    // An invisible overlay that captures tap gestures
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            selectedPoint = location
                        }
                    
                    // If a point has been selected, draw an icon at that position
                    if let point = selectedPoint {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .stroke(accentColor, lineWidth: 2)
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            )
                            .position(x: point.x, y: point.y) // Position the icon at the tap location
                            .shadow(radius: 5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }
    
    // The custom playback controls (play/pause, slider, time labels)
    private var customControlsView: some View {
        HStack(spacing: 12) {
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }
            
            TimeLabel(time: viewModel.currentTime)
            
            // A slider bound to the view model's current time
            Slider(value: Binding(
                // GET: The slider's value is the player's current time
                get: { viewModel.currentTime },
                // SET: When the user drags the slider
                set: { newTime in
                    // seek the player to the new time and pause it
                    viewModel.seek(to: newTime)
                    viewModel.player.pause()
                }
            ), in: 0...max(viewModel.duration, 0.1))
            .tint(accentColor)
            
            TimeLabel(time: viewModel.duration)
        }
        .padding(.vertical, 8)
    }
    
    // The footer containing the main navigation buttons ("Back", "Continue").
    // This view shows different buttons and logic depending on `isFrameConfirmed`.
    private var footerButtons: some View {
        VStack(spacing: 15) {
            if !isFrameConfirmed {
                // --- STEP 1: SELECT SCENE ---
                HStack(spacing: 12) {
                    Button {
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 24)
                        .background(
                            Capsule()
                                .fill(BrandColors.lightGray.opacity(0.7))
                        )
                    }
                    
                    Button {
                        withAnimation {
                            isFrameConfirmed = true // Move to step 2 (pinpoint)
                            viewModel.player.pause() // Pause player for pinpointing
                            step = .pinpoint // Update progress bar
                        }
                    } label: {
                        HStack {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(Capsule())
                        .shadow(color: accentColor.opacity(0.3), radius: 10, y: 5)
                    }
                }
                .padding(.horizontal)

            } else {
                // --- STEP 2: PINPOINT ---
                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            isFrameConfirmed = false // Go back to step 1 (scrubbing)
                            selectedPoint = nil // Clear the selected point
                            step = .selectScene // Update progress bar
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 24)
                        .background(
                            Capsule()
                                .fill(BrandColors.lightGray.opacity(0.7))
                        )
                    }
                    
                    Button {
                        navigateToProcessing = true // Trigger navigation to the next screen
                    } label: {
                        HStack {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(Capsule())
                        .shadow(color: accentColor.opacity(0.3), radius: 10, y: 5)
                    }
                    // Disable the "Continue" button until the user has selected a point
                    .disabled(selectedPoint == nil)
                    .opacity(selectedPoint == nil ? 0.6 : 1.0)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 24)
        .background(BrandColors.backgroundGradientEnd)
    }
}
