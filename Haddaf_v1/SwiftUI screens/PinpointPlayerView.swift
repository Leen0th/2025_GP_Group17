//
//  PinpointPlayerView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 19/10/2025.
//

import SwiftUI
import AVKit
import Combine

// MARK: - Player View Model (The Fix)
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

    // MODIFIED: deinit removed and replaced with this cleanup function.
    // This function will be called from the view to safely remove observers.
    func cleanup() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.removeObserver(self, forKeyPath: "timeControlStatus")
        player.pause()
    }

    private func setupPlayer() {
        // Get video duration asynchronously
        Task {
            if let duration = try? await player.currentItem?.asset.load(.duration) {
                self.duration = duration.seconds
            }
        }

        // Listen for time updates
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        // Listen for play/pause state using KVO
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
        player.seek(to: targetTime)
    }
}


// A helper view to format the video time (e.g., 00:15)
fileprivate struct TimeLabel: View {
    let time: TimeInterval
    
    private static var formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    var body: some View {
        Text(Self.formatter.string(from: time) ?? "00:00")
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
    }
}


// MARK: - Main View (Updated)
struct PinpointPlayerView: View {
    // Inputs & Environment
    let videoURL: URL
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel: PlayerViewModel
    
    // UI State
    @State private var isFrameConfirmed = false
    @State private var selectedPoint: CGPoint?
    @State private var navigateToProcessing = false

    private let accentColor = Color(hex: "#36796C")

    init(videoURL: URL) {
        self.videoURL = videoURL
        _viewModel = StateObject(wrappedValue: PlayerViewModel(videoURL: videoURL))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                instructionsView
                
                videoPlayerWithTapArea
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                customControlsView
                    .padding(.horizontal)
                    .disabled(isFrameConfirmed)
                    .opacity(isFrameConfirmed ? 0.5 : 1.0)
                
                Spacer()
                
                footerButtons
            }
            .background(Color.white)
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            // MODIFIED: .onDisappear now calls the safe cleanup() function.
            .onDisappear { viewModel.cleanup() }
            .navigationDestination(isPresented: $navigateToProcessing) {
                if let point = selectedPoint {
                    ProcessingVideoView(videoURL: videoURL, pinpoint: point)
                }
            }
        }
    }
    
    // MARK: - Subviews

    private var headerView: some View {
        ZStack {
            Text("Pinpoint Position")
                .font(.custom("Poppins", size: 28))
                .fontWeight(.medium)
                .foregroundColor(accentColor)
            
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var instructionsView: some View {
        HStack {
            Image(systemName: isFrameConfirmed ? "2.circle.fill" : "1.circle.fill")
                .font(.title2)
                .foregroundColor(accentColor)
            
            Text(isFrameConfirmed ? "Now, tap your position on the video." : "Use the timeline to find the perfect frame.")
                .font(.custom("Poppins", size: 16))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .animation(.easeInOut, value: isFrameConfirmed)
    }

    private var videoPlayerWithTapArea: some View {
        ZStack {
            VideoPlayer(player: viewModel.player)
                .aspectRatio(9/16, contentMode: .fit)
                .onTapGesture {
                    guard isFrameConfirmed else { return }
                    viewModel.player.pause()
                }

            if isFrameConfirmed {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            self.selectedPoint = location
                        }

                    if let point = selectedPoint {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Circle().stroke(accentColor, lineWidth: 2))
                            .position(x: point.x, y: point.y)
                            .shadow(radius: 5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var customControlsView: some View {
        HStack(spacing: 12) {
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }

            TimeLabel(time: viewModel.currentTime)

            Slider(value: Binding(get: {
                viewModel.currentTime
            }, set: { newTime in
                viewModel.seek(to: newTime)
            }), in: 0...viewModel.duration)
            .tint(accentColor)
            
            TimeLabel(time: viewModel.duration)
        }
        .padding(.vertical, 8)
    }

    private var footerButtons: some View {
        VStack(spacing: 15) {
            if !isFrameConfirmed {
                Button("Confirm Frame") {
                    withAnimation {
                        isFrameConfirmed = true
                        viewModel.player.pause()
                    }
                }
                .font(.custom("Poppins", size: 18)).fontWeight(.semibold)
                .foregroundColor(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 25.0).stroke(accentColor, lineWidth: 2))
                .padding(.horizontal)
            } else {
                Button("Edit Frame") {
                    withAnimation {
                        isFrameConfirmed = false
                        selectedPoint = nil
                    }
                }
                .font(.custom("Poppins", size: 18)).fontWeight(.semibold)
                .foregroundColor(.secondary)
            }
            
            Button("Continue") {
                navigateToProcessing = true
            }
            .font(.custom("Poppins", size: 18)).fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accentColor)
            .clipShape(Capsule())
            .padding(.horizontal)
            .disabled(selectedPoint == nil)
            .opacity(selectedPoint == nil ? 0.6 : 1.0)
        }
        .padding(.bottom, 24)
    }
}
