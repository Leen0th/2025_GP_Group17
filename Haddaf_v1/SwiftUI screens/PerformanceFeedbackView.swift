//
//  PerformanceFeedbackView.swift
//  Haddaf_v1
//
//  Created by Lujain Alhussan on 17/04/1447 AH.
//

import SwiftUI

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

// MARK: - Video Placeholder
struct PerformanceVideoPlaceholderView: View {
    var body: some View {
        ZStack {
            Image("post_placeholder2") // ← تأكدي أن الصورة موجودة في Assets
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

// MARK: - Stat Bar
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

// MARK: - Main View
struct PerformanceFeedbackView: View {
    @State private var selectedTab: Tab = .profile
    @State private var showVideoUpload = false

    private let primary = Color(hex: "#36796C")
    @State private var caption: String = ""
    enum Visibility { case `public`, `private` }
    @State private var visibility: Visibility = .public

    private let stats: [PFPostStat] = [
        .init(label: "GOALS", value: 2, maxValue: 5),
        .init(label: "TOTAL ATTEMPTS", value: 9, maxValue: 20),
        .init(label: "BLOCKED", value: 3, maxValue: 10),
        .init(label: "SHOTS ON TARGET", value: 12, maxValue: 20),
        .init(label: "CORNERS", value: 9, maxValue: 15),
        .init(label: "OFFSIDES", value: 4, maxValue: 10),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // Video
                    PerformanceVideoPlaceholderView()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // Stats
                    VStack(spacing: 16) {
                        ForEach(stats) { s in
                            PFStatBarView(stat: s, accent: primary)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Add caption + Post visibility section
                    VStack(alignment: .leading, spacing: 18) {
                        // Add caption
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a caption :")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(.gray) // ← صار رمادي

                            TextField("", text: $caption, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray3), lineWidth: 1)
                                        .background(.white)
                                )
                        }
                        .padding(.horizontal, 16)

                        // Post Visibility
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Post Visibility :")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(.gray)
                                .padding(.leading, 16)

                            HStack(spacing: 40) {
                                visibilityOption(title: "public", isSelected: visibility == .public)
                                    .onTapGesture { visibility = .public }
                                visibilityOption(title: "private", isSelected: visibility == .private)
                                    .onTapGesture { visibility = .private }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                        }
                    }
                    .padding(.top, 4) // ← رفع بسيط عن الفوتر

                    // Post Button
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120) // مساحة للفوتر
                }
            }

            // ✅ Footer ثابت بالأسفل
            CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)
        }
        .sheet(isPresented: $showVideoUpload) { VideoUploadView() }
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Helper
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

#Preview {
    NavigationStack {
        PerformanceFeedbackView()
    }
}
