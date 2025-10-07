//
//  SplashVideoView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 06/10/2025.
//

import SwiftUI
import AVKit
import UIKit

struct SplashVideoView: View {
    var body: some View {
        CustomVideoPlayerView()
            .ignoresSafeArea()
            // ensures the video doesn't get stretched or take up more space than it should
            .aspectRatio(contentMode: .fit)
    }
}

fileprivate struct CustomVideoPlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        // instance of our custom view that plays the video
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

        // Find the video file in project
        guard let fileUrl = Bundle.main.url(forResource: "SplashAnimation", withExtension: "mov") else {
            print("Error: Could not find video file 'SplashAnimation.mov'")
            return
        }

        // Create the player
        let player = AVPlayer(url: fileUrl)
        player.play() // Start playing immediately.

        // Create the AVPlayerLayer and add it to the view's layer
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect // Ensures the video fits without being stretched
        layer.addSublayer(playerLayer)

        // set the background of our custom view to clear. to allows the
        // white background from ContentView to show through
        self.backgroundColor = .clear

        // Add a notification to loop the video.
        // Twaits for the video to end, then seeks back to the beginning and plays it again
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }

    // This function is called whenever the view's size changes
    // update the player layer's frame to match, so it's always centered
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

