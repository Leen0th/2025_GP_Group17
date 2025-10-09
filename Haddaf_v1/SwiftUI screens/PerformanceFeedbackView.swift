//
//  PerformanceFeedbackView.swift
//  Haddaf_v1
//
//  Created by Lujain Alhussan on 17/04/1447 AH.
//

import SwiftUI
import PhotosUI
import AVKit // Import for VideoPlayer

// MARK: - Color Extension (Unchanged)
extension Color {
    init(hexval: String) {
        let h = hexval.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3: (a, r, g, b) = (255, (int>>8)*17, (int>>4 & 0xF)*17, (int & 0xF)*17)
        case 6: (a, r, g, b) = (255, int>>16, int>>8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int>>24, int>>16 & 0xFF, int>>8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Models (Unchanged)
struct PFPostStat: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let maxValue: Int
}

// MARK: - Stat Bar (Unchanged)
struct PFStatBarView: View {
    let stat: PFPostStat
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.semibold)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                    .frame(height: 6)
                GeometryReader { geo in
                    let ratio = max(0, min(1, Double(stat.value) / Double(stat.maxValue)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent)
                        .frame(width: geo.size.width * ratio, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Main View (REWRITTEN)
struct PerformanceFeedbackView: View {
    // 1. ACCEPT the selected video from the previous screen
    let selectedVideoItem: PhotosPickerItem
    
    // 2. State for the video player and UI
    @State private var player: AVPlayer?
    @State private var caption: String = ""
    enum Visibility { case `public`, `private` }
    @State private var visibility: Visibility = .public

    private let primary = Color(hexval: "#36796C")
    
    // Using your existing placeholder stats
    private let stats: [PFPostStat] = [
        .init(label: "GOALS", value: 2, maxValue: 5),
        .init(label: "TOTAL ATTEMPTS", value: 9, maxValue: 20),
        .init(label: "BLOCKED", value: 3, maxValue: 10),
        .init(label: "SHOTS ON TARGET", value: 12, maxValue: 20),
        .init(label: "CORNERS", value: 9, maxValue: 15),
        .init(label: "OFFSIDES", value: 4, maxValue: 10),
    ]

    var body: some View {
        // This view is now a simple ScrollView, not a ZStack with a tab bar.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // 3. VIDEO PLAYER that loads the selected video
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    // Show a loading indicator while the video is prepared
                    ProgressView()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                }
                
                // Stats section
                VStack(spacing: 16) {
                    ForEach(stats) { s in
                        PFStatBarView(stat: s, accent: primary)
                    }
                }

                // Caption and Visibility sections
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a caption :")
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(.gray)

                        TextField("", text: $caption, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray3), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Post Visibility :")
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(.gray)

                        HStack(spacing: 40) {
                            visibilityOption(title: "public", isSelected: visibility == .public)
                                .onTapGesture { visibility = .public }
                            visibilityOption(title: "private", isSelected: visibility == .private)
                                .onTapGesture { visibility = .private }
                        }
                    }
                }
                .padding(.top, 4)

                // Post Button
                Button {
                    // TODO: Handle post action (upload video data, caption, etc. to Firestore)
                } label: {
                    Text("post")
                        .textCase(.lowercase)
                        .font(.custom("Poppins", size: 18))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 16) // Apply horizontal padding to the whole content stack
        }
        .background(Color.white)
        .navigationTitle("Performance Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadVideo) // 4. Load the video when the view appears
    }

    // MARK: - Helper Methods
    private func visibilityOption(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(primary)
            Text(title)
                .font(.custom("Poppins", size: 16))
                .foregroundColor(primary)
        }
    }
    
    // 5. FUNCTION to load the video from the PhotosPickerItem
    private func loadVideo() {
        Task {
            do {
                if let videoURL = try await selectedVideoItem.loadTransferable(type: URL.self) {
                    await MainActor.run {
                        self.player = AVPlayer(url: videoURL)
                    }
                }
            } catch {
                print("Error loading video: \(error.localizedDescription)")
            }
        }
    }
}
