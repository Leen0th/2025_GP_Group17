//
//  PinpointPlayerView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 19/10/2025.
//

import SwiftUI
import AVKit
import Combine

// MARK: - Player View Model
@MainActor
class PlayerViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer
    @Published var isPlaying = false
    @Published var duration: TimeInterval = 0.0
    @Published var currentTime: TimeInterval = 0.0
    
    private var timeObserver: Any?

    init(videoURL: URL) {
        self.player = AVPlayer(url: videoURL)
        super.init()
        setupPlayer()
    }

    func cleanup() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        player.pause()
    }

    private func setupPlayer() {
        Task {
            if let duration = try? await player.currentItem?.asset.load(.duration) {
                self.duration = duration.seconds
            }
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "timeControlStatus" {
            self.isPlaying = self.player.timeControlStatus == .playing
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(to time: TimeInterval) {
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

// Helper: Time Label
fileprivate struct TimeLabel: View {
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
    let videoURL: URL
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel: PlayerViewModel
    
    // UI State
    @State private var isFrameConfirmed = false
    @State private var selectedPoint: CGPoint?
    @State private var navigateToProcessing = false
    @State private var frameWidth: CGFloat = 1920 // Fallback
    @State private var frameHeight: CGFloat = 1080 // Fallback
    
    // MODIFIED: Use new BrandColors
    private let accentColor = BrandColors.darkTeal
    
    init(videoURL: URL, isPresented: Binding<Bool>) {
        self.videoURL = videoURL
        self._isPresented = isPresented
        _viewModel = StateObject(wrappedValue: PlayerViewModel(videoURL: videoURL))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                instructionsView
                
                videoPlayerWithOverlay
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                    .padding(.horizontal)
                
                if !isFrameConfirmed {
                    customControlsView
                        .padding(.horizontal)
                        .transition(.opacity)
                }
                
                Spacer()
                footerButtons
            }
            .background(BrandColors.backgroundGradientEnd)
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            .onAppear {
                // Load video dimensions
                Task {
                    do {
                        let asset = AVAsset(url: videoURL)
                        if let track = try await asset.loadTracks(withMediaType: .video).first {
                            let size = try await track.load(.naturalSize)
                            frameWidth = size.width
                            frameHeight = size.height
                            print("📏 Video dimensions: \(frameWidth)x\(frameHeight)")
                        }
                    } catch {
                        print("⚠️ Error loading video dimensions: \(error)")
                    }
                }
            }
            .onDisappear { viewModel.cleanup() }
            .navigationDestination(isPresented: $navigateToProcessing) {
                if let point = selectedPoint {
                    ProcessingVideoView(videoURL: videoURL, pinpoint: point, frameWidth: frameWidth, frameHeight: frameHeight)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        ZStack {
            Text("Spot Yourself in Action")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(accentColor)
            
            HStack {
                Button { isPresented = false } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .padding(10)
                        .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                }
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private var instructionsView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFrameConfirmed ? "2.circle.fill" : "1.circle.fill")
                .font(.title2)
                .foregroundColor(accentColor)
            
            Text(isFrameConfirmed
                ? "Tap on yourself in the video to mark your position clearly. Then click Continue to proceed."
                : "Use the timeline below to find a scene where you are fully visible. Then click Confirm Scene.")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .animation(.easeInOut, value: isFrameConfirmed)
    }
    
    private var videoPlayerWithOverlay: some View {
        ZStack {
            VideoPlayer(player: viewModel.player)
                .disabled(true)
                .aspectRatio(9/16, contentMode: .fit)
                .allowsHitTesting(false)
            
            if isFrameConfirmed {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            selectedPoint = location
                        }
                    
                    if let point = selectedPoint {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .stroke(accentColor, lineWidth: 2)
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            )
                            .position(x: point.x, y: point.y)
                            .shadow(radius: 5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }
    
    private var customControlsView: some View {
        HStack(spacing: 12) {
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }
            
            TimeLabel(time: viewModel.currentTime)
            
            Slider(value: Binding(
                get: { viewModel.currentTime },
                set: { newTime in
                    viewModel.seek(to: newTime)
                    viewModel.player.pause()
                }
            ), in: 0...max(viewModel.duration, 0.1))
            .tint(accentColor)
            
            TimeLabel(time: viewModel.duration)
        }
        .padding(.vertical, 8)
    }
    
    private var footerButtons: some View {
        VStack(spacing: 15) {
            if !isFrameConfirmed {
                Button {
                    withAnimation {
                        isFrameConfirmed = true
                        viewModel.player.pause()
                    }
                } label: {
                    HStack {
                        Text("Confirm Scene")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Image(systemName: "checkmark")
                    }
                    .foregroundColor(accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(accentColor, lineWidth: 2)
                            .background(BrandColors.background.clipShape(Capsule()))
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                }
                .padding(.horizontal)
            } else {
                Button {
                    withAnimation {
                        isFrameConfirmed = false
                        selectedPoint = nil
                    }
                } label: {
                    HStack {
                        Text("Change Scene")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.left")
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Button {
                navigateToProcessing = true
            } label: {
                HStack {
                    Text("Continue")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentColor)
                .clipShape(Capsule())
                .shadow(color: accentColor.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal)
            .disabled(selectedPoint == nil)
            .opacity(selectedPoint == nil ? 0.6 : 1.0)
        }
        .padding(.bottom, 24)
    }
}
