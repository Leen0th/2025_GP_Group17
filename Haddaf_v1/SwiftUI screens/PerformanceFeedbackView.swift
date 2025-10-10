//
//  PerformanceFeedbackView.swift
//  Haddaf_v1
//
//  Created by Lujain Alhussan on 17/04/1447 AH.
//

import SwiftUI

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

// MARK: - New Video Placeholder (Adapted from your PostViews file)
struct PerformanceVideoPlaceholderView: View {
    var body: some View {
        ZStack {
            // Ensure you have an image named "post_placeholder2" in your Assets
            Image("post_placeholder2")
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .clipped()

            Color.black.opacity(0.25)

            VStack {
                Spacer()
                HStack(spacing: 36) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill").font(.system(size: 42, weight: .bold))
                    Image(systemName: "forward.fill")
                }
                Spacer()
                HStack {
                    Text("3:21")
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.35))
            }
            .foregroundColor(.white)
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}


// MARK: - Stat Bar (Unchanged)
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

// MARK: - Main View (Rewritten to be Standalone)
struct PerformanceFeedbackView: View {
    // REMOVED: No longer needs selectedVideoItem or AVPlayer state
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

                // ✅ Video section now uses the placeholder
                PerformanceVideoPlaceholderView()
                
                // Stats section (Unchanged)
                VStack(spacing: 12) {
                    ForEach(stats) { s in
                        PFStatBarView(stat: s, accent: primary)
                    }
                }

                // Caption + Visibility section (Unchanged)
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

                // Post Button (Unchanged)
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
            .padding(.horizontal, 16)
        }
        .background(Color.white)
        .navigationTitle("Performance Feedback")
        .navigationBarTitleDisplayMode(.inline)
        // REMOVED: .onAppear is no longer needed to load a video
    }

    // MARK: - Helpers (Unchanged)
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
}
