import SwiftUI
import AVKit
import UIKit

struct SplashVideo: View {
    var onSkip: () -> Void

    var body: some View {
        CustomVideoPlayerView()
            .ignoresSafeArea()
            .aspectRatio(contentMode: .fit)
            .contentShape(Rectangle()) // entire video is tappable
            .onTapGesture {
                onSkip()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Continue")
            .accessibilityHint("Tap to skip the splash and continue")
    }
}

// MARK: - CustomVideoPlayerView (UIViewRepresentable)
fileprivate struct CustomVideoPlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        PlayerUIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}

// MARK: - PlayerUIView
fileprivate class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Load local video "SplashAnimation.mov" from bundle
        guard let fileUrl = Bundle.main.url(forResource: "SplashAnimation", withExtension: "mov") else {
            print("Error: Could not find video file 'SplashAnimation.mov'")
            return
        }

        let player = AVPlayer(url: fileUrl)
        self.player = player
        player.play()

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        backgroundColor = .clear

        // Loop the video
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player?.pause()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
