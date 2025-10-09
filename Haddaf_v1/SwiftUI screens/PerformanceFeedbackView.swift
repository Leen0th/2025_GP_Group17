//
//  PerformanceFeedbackView.swift
//  Haddaf_v1
//

import SwiftUI
import PhotosUI
import AVKit

// MARK: - Color Extension
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

// MARK: - Models
struct PFPostStat: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let maxValue: Int
}

// MARK: - Stat Bar  (مطابق لستايل PostStatBarView)
struct PFStatBarView: View {
    let stat: PFPostStat
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: Double(stat.value), total: Double(stat.maxValue))
                .tint(accent)
        }
    }
}

// MARK: - Main View
struct PerformanceFeedbackView: View {
    let selectedVideoItem: PhotosPickerItem
    
    @State private var player: AVPlayer?
    @State private var caption: String = ""
    enum Visibility { case `public`, `private` }
    @State private var visibility: Visibility = .public

    private let primary = Color(hexval: "#36796C")
    
    private let stats: [PFPostStat] = [
        .init(label: "GOALS", value: 2, maxValue: 5),
        .init(label: "TOTAL ATTEMPTS", value: 9, maxValue: 20),
        .init(label: "BLOCKED", value: 3, maxValue: 10),
        .init(label: "SHOTS ON TARGET", value: 12, maxValue: 20),
        .init(label: "CORNERS", value: 9, maxValue: 15),
        .init(label: "OFFSIDES", value: 4, maxValue: 10),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {

                // Video
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ProgressView()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                }
                
                // Stats (spacing مطابق لصفحة Post)
                VStack(spacing: 12) {
                    ForEach(stats) { s in
                        PFStatBarView(stat: s, accent: primary)
                    }
                }

                // Caption + Visibility (بدون تغيير)
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

                Button {
                    // TODO: Handle post action
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
            .padding(.horizontal, 16) // نفس فكرة PostView .padding(.horizontal)
        }
        .background(Color.white)
        .navigationTitle("Performance Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadVideo)
    }

    // MARK: - Helpers
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
