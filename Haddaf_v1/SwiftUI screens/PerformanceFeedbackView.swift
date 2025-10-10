
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

// MARK: - Video Placeholder (Optimized to match PostDetailView)
struct PerformanceVideoPlaceholderView: View {
    let imageName: String = "post_placeholder2"
    
    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 250)
                .background(Color.black)
                .clipped()

            Color.black.opacity(0.3)

            VStack {
                Spacer()
                HStack(spacing: 40) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill").font(.system(size: 40))
                    Image(systemName: "forward.fill")
                }
                Spacer()
                HStack {
                    Text("3:21")
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .padding(12)
                .background(.black.opacity(0.4))
            }
            .font(.callout)
            .foregroundColor(.white)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}


// MARK: - Stat Bar (Optimized to match PostDetailView)
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
            }
            ProgressView(value: Double(stat.value), total: Double(stat.maxValue))
                .tint(accent)
        }
    }
}

// MARK: - Main View (Corrected for PostDetailView alignment)
struct PerformanceFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
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
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                        
                    PerformanceVideoPlaceholderView()
                    
                    // Stats section
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(stats) { s in
                            PFStatBarView(stat: s, accent: primary)
                        }
                    }
                    
                    // قسم التسمية والرؤية - تم التعديل هنا
                    VStack(alignment: .leading, spacing: 18) {
                        
                        // التسمية - تعديل اللون والجرأة
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a caption :")
                                .font(.subheadline)
                                .fontWeight(.medium) // بولد شوي
                                .foregroundColor(.secondary) // رمادي

                            TextField("", text: $caption, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray3), lineWidth: 1)
                                        .background(Color.white)
                                )
                                .cornerRadius(12)
                        }
                        .padding(.top, 4)
                        
                        // الرؤية - تعديل اللون والجرأة والترتيب الرأسي
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Post Visibility :")
                                .font(.subheadline)
                                .fontWeight(.medium) // بولد شوي
                                .foregroundColor(.secondary) // رمادي
                            
                            // الخيارات تحت العنوان
                            HStack(spacing: 40) {
                                visibilityOption(title: "public", isSelected: visibility == .public)
                                    .onTapGesture { visibility = .public }
                                
                                visibilityOption(title: "private", isSelected: visibility == .private)
                                    .onTapGesture { visibility = .private }
                            }
                        }
                        .padding(.top, 10)

                        Spacer().frame(height: 100)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            .background(Color.white)
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            
            // Post Button (مثبت في الأسفل)
            VStack {
                Button {
                    // TODO: Handle post action
                } label: {
                    Text("post")
                        .textCase(.lowercase)
                        .font(.custom("Poppins", size: 18))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(.white)
        }
    }
    
    // MARK: - Header View
    private var header: some View {
        ZStack {
            Text("Performance Feedback")
                .font(.custom("Poppins", size: 28))
                .fontWeight(.medium)
                .foregroundColor(primary)
                .offset(y: 6)
            
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
            }
        }.padding(.bottom, 8)
    }

    // MARK: - Helpers
    private func visibilityOption(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(primary)
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}
