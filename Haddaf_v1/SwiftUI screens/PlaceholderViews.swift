import SwiftUI
import PhotosUI

// MARK: - Placeholder Tab Screens
struct DiscoveryView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Discovery Page").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}

struct TeamsView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Teams Page").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}

struct ChallengeView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Challenge Page").font(.largeTitle).foregroundColor(.secondary)
        }
    }
}


// MARK: - Video Upload View (Trimming Removed)
struct VideoUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideoItem: PhotosPickerItem?
    
    // Simplified navigation state
    @State private var navigateToProcessing = false
    
    let accentColor = Color(hex: "#36796C")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Upload Your Video")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(accentColor)
                    
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)

                Spacer()

                // Main upload area
                VStack {
                    Spacer()
                    Image(systemName: "arrow.down.to.line.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(accentColor.opacity(0.7))
                    Spacer()
                    PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                        Text("Choose Video")
                            .font(.custom("Poppins", size: 18)).fontWeight(.semibold)
                            .foregroundColor(.white).padding(.horizontal, 40)
                            .padding(.vertical, 12).background(accentColor)
                            .clipShape(Capsule())
                    }
                    Spacer().frame(height: 30)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1.0, contentMode: .fit)
                .background(
                    ZStack {
                        Image("upload_background").resizable().aspectRatio(contentMode: .fill).clipped()
                        Color.white.opacity(0.3)
                    }
                )
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .foregroundColor(accentColor.opacity(0.4))
                )
                .cornerRadius(20)
                .padding(.horizontal)

                Spacer()
                Spacer()
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                // When a video is picked, navigate directly
                if newItem != nil {
                    navigateToProcessing = true
                }
            }
            .navigationDestination(isPresented: $navigateToProcessing) {
                // Pass the selected item to the processing view
                if let item = selectedVideoItem {
                    ProcessingVideoView(selectedVideoItem: item)
                }
            }
        }
    }
}
