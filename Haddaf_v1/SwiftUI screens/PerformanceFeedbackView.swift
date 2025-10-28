import SwiftUI
import AVKit

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
    
    let gradient: LinearGradient
    
    init(stat: PFPostStat) {
        self.stat = stat
        
        // Assign gradient based on label
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
            HStack {
                Text(stat.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrandColors.lightGray)
                        .frame(height: 8)
                    
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

// MARK: - AVPlayerViewController wrapper (Unchanged)
struct AVKitPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    class Coordinator {
        var itemObservation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        
        guard vc.player !== player else { return }
        
        vc.player = player
        
        context.coordinator.itemObservation?.invalidate()
        context.coordinator.itemObservation = nil
        
        guard let item = player?.currentItem else {
            return
        }

        context.coordinator.itemObservation = item.observe(\.status, options: [.new, .initial]) { [weak vc] (playerItem, change) in
            
            if playerItem.status == .readyToPlay {
                vc?.player?.pause()
                vc?.player?.seek(to: .zero)
            }
        }
    }
}

// MARK: - Main View (Unchanged)
struct PerformanceFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VideoProcessingViewModel

    @State private var title: String = ""
    private let titleLimit = 15

    @State private var isPrivate: Bool = false
    @State private var postingError: String? = nil

    @State private var matchDate: Date? = nil
    @State private var showDateSheet = false
    @State private var tempSheetDate: Date = Date()

    @State private var player: AVPlayer? = nil
    @State private var endObserver: NSObjectProtocol? = nil
    
    @State private var showExitWarning = false
    @State private var isAnimating = false

    private let primary = BrandColors.darkTeal

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
    
    private var isPostButtonDisabled: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > titleLimit || viewModel.isUploading
    }

    var body: some View {
        // --- MODIFIED: Removed progress bar from here ---
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        
                        // --- MODIFIED: Timeline moved here ---
                        MultiStepProgressBar(currentStep: .feedback)
                        
                        videoSection
                        statsSection
                        titleVisibilitySection // This section is now fixed
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
        .alert("Discard Video", isPresented: $showExitWarning) {
            Button("Discard", role: .destructive) {
                cancelAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to discard your video and performance analysis?")
        }
        .alert("Error", isPresented: .constant(postingError != nil)) {
            Button("OK") { postingError = nil }
        } message: { Text(postingError ?? "Unknown error occurred") }
        .onChange(of: title) { _, newVal in
            if newVal.count > titleLimit { title = String(newVal.prefix(titleLimit)) }
        }
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

    // MARK: - Header (Unchanged)
    private var header: some View {
        ZStack {
            Text("Performance Feedback")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(primary)
                .offset(y: 6)

            HStack {
                Spacer()
                Button {
                    showExitWarning = true
                } label: {
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

    // MARK: - Video (Unchanged)
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
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    // MARK: - Stats (Unchanged)
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Performance Analysis")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .padding(.bottom, 4)
            
            ForEach(viewModel.performanceStats) { s in
                PFStatBarView(stat: s)
            }
        }
        .padding(20)
        .background(BrandColors.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    // MARK: - Title + Visibility (FIXED)
    private var titleVisibilitySection: some View {
        // This VStack is now correctly styled as a card
        VStack(alignment: .leading, spacing: 18) {
            // Title (mandatory)
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

                TextField("Enter a short title…", text: $title)
                    .font(.system(size: 16, design: .rounded))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        // FIX: Changed fill to contrast with the parent card
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BrandColors.lightGray.opacity(0.7)) // <-- CHANGED
                            // .shadow(...) // <-- REMOVED shadow from inner element
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                    .cornerRadius(12) // Note: This .cornerRadius is redundant, but harmless
                    .accessibilityLabel("Post title (required)")
            }
            .padding(.top, 4)

            // Visibility
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
                        // FIX: Changed fill to contrast with the parent card
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BrandColors.lightGray.opacity(0.7)) // <-- CHANGED
                            // .shadow(...) // <-- REMOVED shadow from inner element
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                }
            }
            .padding(.top, 6)
        }
        // FIX: Added card modifiers to the whole section
        .padding(20)
        .background(BrandColors.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    // MARK: - Match Date Row (Unchanged)
    private var dateRowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match Date (optional)")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

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

    // MARK: - Post Button (Unchanged)
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

    // MARK: - Player setup / teardown (Unchanged)
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

    // MARK: - Helpers (Unchanged)
    private func cancelAndDismiss() {
        teardownPlayer()
        viewModel.resetAfterPosting()
        NotificationCenter.default.post(name: Notification.Name("cancelUploadFlow"), object: nil)
    }
}
