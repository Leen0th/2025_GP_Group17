//
//  SplashVideoView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 06/10/2025.
//
import SwiftUI
import AVKit
import UIKit

// This is the main view you will use in ContentView. It's clean and simple.
struct SplashVideoView: View {
    var body: some View {
        // We are now using our custom player instead of the default VideoPlayer.
        CustomVideoPlayerView()
            .ignoresSafeArea()
            // The aspect ratio modifier ensures the video doesn't get stretched or
            // take up more space than it should, respecting transparency.
            .aspectRatio(contentMode: .fit)
    }
}

// A helper struct that wraps our custom UIKit View, making it usable in SwiftUI.
fileprivate struct CustomVideoPlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        // Creates an instance of our custom view that plays the video.
        return PlayerUIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // This function is required, but we don't need to put anything here.
    }
}

// The custom UIView class that builds the video player layer.
fileprivate class PlayerUIView: UIView {
    private var playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        // 1. Find the video file in your project.
        guard let fileUrl = Bundle.main.url(forResource: "SplashAnimation", withExtension: "mov") else {
            print("Error: Could not find video file 'SplashAnimation.mov'")
            return
        }

        // 2. Create the player.
        let player = AVPlayer(url: fileUrl)
        player.play() // Start playing immediately.

        // 3. Create the AVPlayerLayer and add it to the view's layer.
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect // Ensures the video fits without being stretched.
        layer.addSublayer(playerLayer)

        // 4. *** THE FIX IS HERE ***
        // We set the background of our custom view to clear. This allows the
        // white background from your ContentView to show through.
        self.backgroundColor = .clear

        // 5. Add a notification to loop the video.
        // This observer waits for the video to end, then seeks back to the
        // beginning and plays it again.
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }

    // This function is called whenever the view's size changes.
    // We update the player layer's frame to match, so it's always centered.
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

