import SwiftUI
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

// MARK: - AVPlayerViewController wrapper (controls visible, primed to show big play)
// MARK: - AVPlayerViewController wrapper (controls visible, primed to show big play)
struct AVKitPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    // 1. Create a Coordinator class to observe the player item
    class Coordinator {
        var itemObservation: NSKeyValueObservation?
    }

    // 2. Implement makeCoordinator
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // 3. makeUIViewController is now simple
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        // We will set the player and observer in 'update'
        return vc
    }

    // 4. updateUIViewController does all the work
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        
        // Don't do anything if the player is the same object
        guard vc.player !== player else { return }
        
        vc.player = player
        
        // Clean up any old observer
        context.coordinator.itemObservation?.invalidate()
        context.coordinator.itemObservation = nil
        
        // Get the new player's item
        guard let item = player?.currentItem else {
            return // No item, nothing to observe
        }

        // 5. Observe the item's 'status' property
        context.coordinator.itemObservation = item.observe(\.status, options: [.new, .initial]) { [weak vc] (playerItem, change) in
            
            // 6. When status is '.readyToPlay', pause and seek
            if playerItem.status == .readyToPlay {
                vc?.player?.pause()
                vc?.player?.seek(to: .zero)
            }
        }
    }
}

// MARK: - Main View
struct PerformanceFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VideoProcessingViewModel

    // Title
    @State private var title: String = ""
    private let titleLimit = 15 // This remains 15 as per your last request

    // Visibility & posting
    @State private var isPrivate: Bool = false
    @State private var postingError: String? = nil

    // Match Date (optional) – bottom sheet
    @State private var matchDate: Date? = nil
    @State private var showDateSheet = false
    @State private var tempSheetDate: Date = Date()

    // Player
    @State private var player: AVPlayer? = nil
    @State private var endObserver: NSObjectProtocol? = nil
    
    @State private var showExitWarning = false
    
    @State private var isAnimating = false

    private let primary = Color(hexval: "#36796C")

    private var customSpinner: some View {
        ZStack {
            // Background circle
            Circle().stroke(lineWidth: 8).fill(Color.gray.opacity(0.1))
            
            // Spinning part
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .fill(primary) // Use 'primary' color from this view
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
        }
        .frame(width: 80, height: 80) // Scaled down from 150
    }
    
    private var isPostButtonDisabled: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > titleLimit || viewModel.isUploading
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    videoSection
                    statsSection
                    titleVisibilitySection
                    dateRowSection
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
            }
            .background(Color.white)
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            .onChange(of: viewModel.videoURL) { _, newURL in
                configurePlayer(with: newURL)
            }
            .onAppear { configurePlayer(with: viewModel.videoURL) }
            .onDisappear { teardownPlayer() }

            postButton
        }
        .disabled(viewModel.isUploading)
        .overlay(
            ZStack {
                if viewModel.isUploading {
                    // Dark background
                    Color.black.opacity(0.4).ignoresSafeArea()
                    
                    // White card
                    VStack(spacing: 20) {
                        
                        // Use the new custom spinner
                        customSpinner
                            .onAppear { isAnimating = true }
                            .onDisappear { isAnimating = false }
                        
                        Text("Posting...")
                            .font(.custom("Poppins", size: 18))
                            .fontWeight(.medium)
                        
                        // Determinate progress bar
                        ProgressView(value: viewModel.uploadProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: primary))
                            .animation(.linear, value: viewModel.uploadProgress)
                            .padding(.horizontal, 20) // Added padding
                        
                        // Percentage text
                        Text(String(format: "%.0f%%", viewModel.uploadProgress * 100))
                            .font(.custom("Poppins", size: 14))
                            .foregroundColor(primary)
                            .animation(nil, value: viewModel.uploadProgress)
                    }
                    .padding(30)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            // Animate the overlay's appearance/disappearance
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isUploading)
        )
        .alert("Discard Video?", isPresented: $showExitWarning) {
            Button("Discard", role: .destructive) {
                cancelAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your video and performance analysis will be discarded.")
        }
        .alert("Error", isPresented: .constant(postingError != nil)) {
            Button("OK") { postingError = nil }
        } message: { Text(postingError ?? "Unknown error occurred") }
        .onChange(of: title) { _, newVal in
            if newVal.count > titleLimit { title = String(newVal.prefix(titleLimit)) }
        }
        // --- MODIFIED SHEET FOR CONSISTENT STYLING ---
        .sheet(isPresented: $showDateSheet) {
            VStack(spacing: 16) {
                // Title (styled like SignUpView)
                Text("Select match date")
                    .font(.custom("Poppins", size: 18))
                    .foregroundColor(primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                // Date Picker (styled like SignUpView)
                DatePicker("", selection: $tempSheetDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(primary)
                    .frame(height: 180)

                // Buttons (styled like SignUpView, but keeping Clear)
                HStack(spacing: 12) {
                    Button("Clear") {
                        matchDate = nil
                        showDateSheet = false
                    }
                    .font(.custom("Poppins", size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundColor(primary.opacity(0.8))
                    .clipShape(Capsule())

                    Button("Done") {
                        matchDate = tempSheetDate
                        showDateSheet = false
                    }
                    .font(.custom("Poppins", size: 18))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(primary)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .presentationDetents([.height(320)]) // Use 320 to fit the 2 buttons
            .presentationBackground(.white) // Added from SignUpView
            .presentationCornerRadius(28) // Added from SignUpView
        }
        // --- END OF MODIFICATION ---
    }

    // MARK: - Header
    private var header: some View {
        ZStack {
            Text("Performance Feedback")
                .font(.custom("Poppins", size: 28))
                .fontWeight(.medium)
                .foregroundColor(primary)
                .offset(y: 6)

            HStack {
                // Back button has been removed
                Spacer()
                
                Button {
                    showExitWarning = true // Show the warning instead of direct dismiss
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Video (AVKit controls visible)
    private var videoSection: some View {
        Group {
            if viewModel.videoURL != nil {
                AVKitPlayerView(player: player)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .frame(height: 250)
                    .overlay(Text("No Video Found").foregroundColor(.white))
            }
        }
    }

    // MARK: - Stats
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.performanceStats) { s in
                PFStatBarView(stat: s, accent: primary)
            }
        }
    }

    // MARK: - Title + Visibility
    private var titleVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title (mandatory)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Add a title")
                        .font(.subheadline).fontWeight(.medium).foregroundColor(.secondary)
                    Text("*").font(.subheadline).fontWeight(.bold).foregroundColor(.red)
                    Spacer()
                    Text("\(title.count)/\(titleLimit)")
                        .font(.caption).foregroundColor(title.count > titleLimit ? .red : .secondary)
                }

                TextField("Enter a short title…", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray3), lineWidth: 1)
                            .background(Color.white)
                    )
                    .cornerRadius(12)
                    .accessibilityLabel("Post title (required)")
            }
            .padding(.top, 4)

            // Visibility
            VStack(alignment: .leading, spacing: 10) {
                Text("Post Visibility")
                    .font(.subheadline).fontWeight(.medium).foregroundColor(.secondary)

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
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Match Date Row
    private var dateRowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match Date (optional)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Button {
                tempSheetDate = matchDate ?? Date()
                showDateSheet = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(primary)
                    Text(matchDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "Select date")
                        .foregroundColor(matchDate == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Post Button
    private var postButton: some View {
        VStack {
            Button {
                Task {
                    do {
                        try await viewModel.createPost(
                            title: title,
                            isPrivate: isPrivate,
                            matchDate: matchDate
                        )
                        viewModel.resetAfterPosting()
                        NotificationCenter.default.post(name: Notification.Name("cancelUploadFlow"), object: nil)
                    } catch {
                        postingError = error.localizedDescription
                    }
                }
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
            .disabled(isPostButtonDisabled)
            .opacity(isPostButtonDisabled ? 0.6 : 1.0)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(.white)
    }

    // MARK: - Player setup / teardown
    private func configurePlayer(with url: URL?) {
        teardownPlayer()

        guard let url else {
            player = nil
            return
        }

        let p = AVPlayer(url: url)
        player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { _ in
            self.player?.seek(to: .zero)
        }
    }

    private func teardownPlayer() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player = nil
    }

    // MARK: - Helpers
    private func cancelAndDismiss() {
        teardownPlayer()
        viewModel.resetAfterPosting()
        NotificationCenter.default.post(name: Notification.Name("cancelUploadFlow"), object: nil)
    }
}
