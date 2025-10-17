import SwiftUI
import AVKit

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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.label).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)").font(.caption).fontWeight(.bold)
            }
            ProgressView(value: Double(stat.value), total: Double(stat.maxValue)).tint(accent)
        }
    }
}

// MARK: - Main View (UPDATED)
struct PerformanceFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VideoProcessingViewModel
    
    @State private var caption: String = ""
    @State private var isPrivate: Bool = false
    @State private var isPosting = false
    @State private var postingError: String? = nil

    private let primary = Color(hexval: "#36796C")
    
    private var isPostButtonDisabled: Bool {
        return caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || caption.count > 100 || isPosting
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    
                    if let url = viewModel.videoURL {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black)
                            .frame(height: 250)
                            .overlay(Text("No Video Found").foregroundColor(.white))
                    }
                    
                    statsSection
                    captionAndVisibilitySection
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            .background(Color.white)
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            
            postButton
        }
        .disabled(isPosting)
        .overlay(
            ZStack { if isPosting { Color.black.opacity(0.4).ignoresSafeArea(); ProgressView().tint(.white) } }
        )
        .alert("Error", isPresented: .constant(postingError != nil)) {
            Button("OK") { postingError = nil }
        } message: { Text(postingError ?? "Unknown error occurred") }
    }
    
    // MODIFIED: Header now contains a cancel button and updated back button logic.
    private var header: some View {
        ZStack {
            Text("Performance Feedback").font(.custom("Poppins", size: 28)).fontWeight(.medium).foregroundColor(primary).offset(y: 6)
            HStack {
                // Both the back and cancel buttons now dismiss the entire upload flow
                // to prevent getting stuck on the processing screen.
                Button { cancelAndDismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
                Button { cancelAndDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }.padding(.bottom, 8)
    }
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.performanceStats) { s in PFStatBarView(stat: s, accent: primary) }
        }
    }
    
    private var captionAndVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Add a caption:").font(.subheadline).fontWeight(.medium).foregroundColor(.secondary)
                    Spacer()
                    Text("\(caption.count)/100")
                        .font(.caption)
                        .foregroundColor(caption.count > 100 ? .red : .secondary)
                }
                TextField("Write something...", text: $caption, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray3), lineWidth: 1).background(Color.white))
                    .cornerRadius(12)
            }.padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Post Visibility:").font(.subheadline).fontWeight(.medium).foregroundColor(.secondary)
                Button(action: { isPrivate.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: isPrivate ? "lock.fill" : "lock.open.fill")
                            .foregroundColor(isPrivate ? .red : primary)
                        Text(isPrivate ? "Private" : "Public")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }.padding(.top, 10)
        }
    }
    
    private var postButton: some View {
        VStack {
            Button {
                Task {
                    isPosting = true
                    do {
                        try await viewModel.createPost(caption: caption, isPrivate: isPrivate)
                        viewModel.resetAfterPosting()
                        // Instead of just dismissing this view, we dismiss the whole flow via notification.
                        NotificationCenter.default.post(name: .cancelUploadFlow, object: nil)
                    } catch {
                        postingError = error.localizedDescription
                    }
                    isPosting = false
                }
            } label: {
                Text("Post")
                    .textCase(.lowercase)
                    .font(.custom("Poppins", size: 18))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(primary)
                    .clipShape(Capsule())
            }
            .disabled(isPostButtonDisabled)
            .opacity(isPostButtonDisabled ? 0.6 : 1.0)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(.white)
    }

    // ADDED: Helper function to clean up state and post notification.
    private func cancelAndDismiss() {
        viewModel.resetAfterPosting()
        NotificationCenter.default.post(name: .cancelUploadFlow, object: nil)
    }
}
