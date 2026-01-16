import SwiftUI
import AVKit

// MARK: - Models
// A model representing a single performance statistic for a post.
struct PFPostStat: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let maxValue: Int
}

// MARK: - Stat Bar
// A view that displays a single performance statistic as a labeled, animated progress bar.
struct PFStatBarView: View {
    // The statistic to display.
    let stat: PFPostStat
    // The color gradient for the bar, customized based on the stat type.
    let gradient: LinearGradient
    
    // Initializes the view and sets the appropriate gradient based on the stat's label.
    init(stat: PFPostStat) {
        self.stat = stat
        // Assign a specific gradient based on the skill name
        switch stat.label.lowercased() {
        case "dribble":
            self.gradient = LinearGradient(colors: [BrandColors.turquoise.opacity(0.7), BrandColors.turquoise], startPoint: .leading, endPoint: .trailing)
        case "pass":
            self.gradient = LinearGradient(colors: [BrandColors.teal.opacity(0.7), BrandColors.teal], startPoint: .leading, endPoint: .trailing)
        case "shoot":
            self.gradient = LinearGradient(colors: [BrandColors.actionGreen.opacity(0.7), BrandColors.actionGreen], startPoint: .leading, endPoint: .trailing)
        default:
            self.gradient = LinearGradient(colors: [BrandColors.darkTeal.opacity(0.7), BrandColors.darkTeal], startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row with label and value
            HStack {
                Text(stat.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
            }
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrandColors.lightGray)
                        .frame(height: 8)
                    // Filled portion of the bar
                    Capsule()
                        .fill(gradient)
                        .frame(width: (geometry.size.width * CGFloat(stat.value) / CGFloat(stat.maxValue)), height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: stat.value)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - AVKit Player Wrapper
struct AVKitPlayerView: UIViewControllerRepresentable {
    // The `AVPlayer` instance that holds the video to be played.
    let player: AVPlayer?
    
    // The coordinator handles observation of the player item.
    class Coordinator {
        // An observer that watches the `status` of an `AVPlayerItem`.
        var itemObservation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // Creates and configures the `AVPlayerViewController`.
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }
    
    // Updates the `AVPlayerViewController` when the `player` property changes.
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Only update if the player instance is different
        guard vc.player !== player else { return }
        vc.player = player
        // Clean up any old observer before setting a new one
        context.coordinator.itemObservation?.invalidate()
        context.coordinator.itemObservation = nil
        
        guard let item = player?.currentItem else { return }

        // Observe the item's status to know when it's ready to play.
        // This is used to pause the video and seek to the beginning immediately upon loading, preventing it from auto-playing.
        context.coordinator.itemObservation = item.observe(\.status, options: [.new, .initial]) { [weak vc] (playerItem, change) in
            if playerItem.status == .readyToPlay {
                // Video is loaded, so pause it and rewind to the start.
                vc?.player?.pause()
                vc?.player?.seek(to: .zero)
            }
        }
    }
}

// MARK: - Main View
// The main view for the Performance Feedback screen.
struct PerformanceFeedbackView: View {
    // Used to dismiss the view.
    @Environment(\.dismiss) private var dismiss
    // The view model containing the video, stats, and upload logic.
    @ObservedObject var viewModel: VideoProcessingViewModel

    // MARK: - State Properties
    // The title for the post, entered by the user.
    @State private var title: String = ""
    private let titleLimit = 15
    // Toggles the post visibility between public and private.
    @State private var isPrivate: Bool = false
    // Holds an error message if posting fails.
    @State private var postingError: String? = nil

    // Phase 1: Position Selection
    @State private var selectedPositionForUpload: String = "Attacker"
    let availablePositions = ["Attacker", "Midfielder", "Defender"]

    // Date
    @State private var matchDate: Date? = nil
    // Controls the presentation of the date picker sheet.
    @State private var showDateSheet = false
    // A temporary date holder for the sheet to avoid non-atomic updates.
    @State private var tempSheetDate: Date = Date()

    // Video Player
    @State private var player: AVPlayer? = nil
    // An observer to detect when the video finishes playing (to loop it).
    @State private var endObserver: NSObjectProtocol? = nil
    
    // UI Helpers
    @State private var showExitWarning = false
    // Controls the animation state of the custom spinner.
    @State private var isAnimating = false

    private let primary = BrandColors.darkTeal

    // MARK: - Computed Views
    // A custom rotating loading spinner.
    private var customSpinner: some View {
        ZStack {
            Circle().stroke(lineWidth: 8).fill(BrandColors.lightGray)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .fill(primary)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
        }
        .frame(width: 80, height: 80)
    }
    
    // Determines if the "Post" button should be disabled.
    private var isPostButtonDisabled: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > titleLimit || viewModel.isUploading
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Main scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        MultiStepProgressBar(currentStep: .feedback)
                        
                        videoSection
                        statsSection
                        
                        // Combined Wrapper (Position + Title + Visibility)
                        inputWrapperSection
                        
                        dateRowSection
                        Spacer().frame(height: 100)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                .background(BrandColors.backgroundGradientEnd)
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
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 20) {
                            customSpinner
                                .onAppear { isAnimating = true }
                                .onDisappear { isAnimating = false }
                            Text("Posting...")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                            ProgressView(value: viewModel.uploadProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: primary))
                                .animation(.linear, value: viewModel.uploadProgress)
                                .padding(.horizontal, 20)
                            Text(String(format: "%.0f%%", viewModel.uploadProgress * 100))
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(primary)
                                .animation(nil, value: viewModel.uploadProgress)
                        }
                        .padding(30)
                        .background(BrandColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
                        .padding(.horizontal, 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isUploading)
            )
        }
        // Alert for discarding the video
        .alert("Discard Video", isPresented: $showExitWarning) {
            Button("Discard", role: .destructive) { cancelAndDismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to discard your video and performance analysis?")
        }
        // Alert for posting errors
        .alert("Error", isPresented: .constant(postingError != nil)) {
            Button("OK") { postingError = nil }
        } message: { Text(postingError ?? "Unknown error occurred") }
        // Enforce title character limit
        .onChange(of: title) { _, newVal in
            if newVal.count > titleLimit { title = String(newVal.prefix(titleLimit)) }
        }
        // Date picker sheet
        .sheet(isPresented: $showDateSheet) {
            VStack(spacing: 16) {
                Text("Select match date")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                DatePicker("", selection: $tempSheetDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(primary)
                    .frame(height: 180)
                HStack(spacing: 12) {
                    Button("Clear") {
                        matchDate = nil
                        showDateSheet = false
                    }
                    .font(.system(size: 16, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(BrandColors.lightGray)
                    .foregroundColor(primary.opacity(0.8))
                    .clipShape(Capsule())
                    Button("Done") {
                        matchDate = tempSheetDate
                        showDateSheet = false
                    }
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(primary)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .presentationDetents([.height(320)])
            .presentationBackground(BrandColors.background)
            .presentationCornerRadius(28)
        }
    }

    // MARK: - Sections
    private var header: some View {
        ZStack {
            Text("Performance Feedback")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(primary)
                .offset(y: 6)
            HStack {
                Spacer()
                Button { showExitWarning = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(BrandColors.lightGray.opacity(0.7))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Video
    // The section displaying the video player.
    private var videoSection: some View {
        Group {
            if viewModel.videoURL != nil {
                AVKitPlayerView(player: player)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Placeholder if video URL is missing
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .frame(height: 250)
                    .overlay(Text("No Video Found").foregroundColor(.white))
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    // MARK: - Stats
    // The section displaying the AI performance stats.
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Performance Analysis")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .padding(.bottom, 4)
            // Loop over stats and create a bar for each
            ForEach(viewModel.performanceStats) { s in
                PFStatBarView(stat: s)
            }
        }
        .padding(20)
        .background(BrandColors.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    // MARK: - Combined Input Section (Position, Title, Visibility)
    private var inputWrapperSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            
            // 1. Position Selection
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Played Position")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("*")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                
                Menu {
                    ForEach(availablePositions, id: \.self) { pos in
                        Button(pos) {
                            selectedPositionForUpload = pos
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedPositionForUpload)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BrandColors.lightGray.opacity(0.7))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                }
            }

            // 2. Title
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Add a title")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("*").font(.subheadline).fontWeight(.bold).foregroundColor(.red)
                    Spacer()
                    Text("\(title.count)/\(titleLimit)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(title.count > titleLimit ? .red : .secondary)
                }

                TextField("", text: $title)
                    .font(.system(size: 16, design: .rounded))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BrandColors.lightGray.opacity(0.7))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                    .cornerRadius(12)
                    .accessibilityLabel("Post title (required)")
            }
            .padding(.top, 4)

            // 3. Visibility
            VStack(alignment: .leading, spacing: 10) {
                Text("Post Visibility")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Button(action: { isPrivate.toggle() }) {
                    HStack(spacing: 12) {
                        Image(systemName: isPrivate ? "lock.fill" : "lock.open.fill")
                            .foregroundColor(isPrivate ? .red : primary)
                        Text(isPrivate ? "Private" : "Public")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BrandColors.lightGray.opacity(0.7))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                }
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(BrandColors.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        
        // Auto-fill default with user's current profile position if available
        .onAppear {
             if let currentUserPos = VideoProcessingViewModel.sharedUserPosition, !currentUserPos.isEmpty {
                 selectedPositionForUpload = currentUserPos
             }
        }
    }

    // MARK: - Match Date Row
    // The section for selecting the optional match date.
    private var dateRowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match Date (optional)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            // Button to open the date picker sheet
            Button {
                tempSheetDate = matchDate ?? Date()
                showDateSheet = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(primary)
                    Text(matchDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "Select date")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(matchDate == nil ? .secondary : BrandColors.darkGray)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                )
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Post Button
    // The floating "Post" button at the bottom of the screen.
    private var postButton: some View {
        VStack {
            Button {
                // Run the upload and post creation in an async Task
                Task {
                    do {
                        try await viewModel.createPost(
                            title: title,
                            isPrivate: isPrivate,
                            matchDate: matchDate,
                            positionAtUpload: selectedPositionForUpload
                        )
                        cancelAndDismiss()
                    } catch {
                        // On failure, show an error alert
                        postingError = error.localizedDescription
                    }
                }
            } label: {
                Text("post")
                    .textCase(.lowercase)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
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
        .background(BrandColors.background)
    }

    // MARK: - Helpers
    private func configurePlayer(with url: URL?) {
        teardownPlayer()
        guard let url else {
            player = nil
            return
        }
        let p = AVPlayer(url: url)
        player = p
        // Add an observer to detect when the video plays to the end
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { _ in
            // When it ends, seek back to the beginning
            self.player?.seek(to: .zero)
        }
    }

    // Cleans up the player and removes observers.
    private func teardownPlayer() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player = nil
    }

    // MARK: - Helpers
    // Cleans up the view model and player, then posts a notification to dismiss the upload flow.
    private func cancelAndDismiss() {
        teardownPlayer()
        viewModel.resetAfterPosting()
        NotificationCenter.default.post(name: Notification.Name("cancelUploadFlow"), object: nil)
    }
}
