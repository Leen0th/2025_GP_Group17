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
struct AVKitPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true        // ← Apple controls on
        vc.videoGravity = .resizeAspect
        // اجعل زر التشغيل يظهر مباشرةً: شغّل ثانيةً وجمّد
        context.coordinator.primeControlsIfNeeded(vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.showsPlaybackControls = true
        context.coordinator.primeControlsIfNeeded(uiViewController)
    }

    final class Coordinator {
        var didPrime = false

        func primeControlsIfNeeded(_ vc: AVPlayerViewController) {
            guard !didPrime, let p = vc.player else { return }
            didPrime = true
            // اضمن أن المؤشر بالبداية ومتوقف
            p.seek(to: .zero)
            p.pause()
            // شغّل بشكل وجيز ثم أوقف لإجبار AVKit على إظهار البانر الكبير
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                p.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    p.pause()
                    p.seek(to: .zero)
                }
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
    private let titleLimit = 25

    // Visibility & posting
    @State private var isPrivate: Bool = false
    @State private var isPosting = false
    @State private var postingError: String? = nil

    // Match Date (optional) – bottom sheet
    @State private var matchDate: Date? = nil
    @State private var showDateSheet = false
    @State private var tempSheetDate: Date = Date()

    // Player
    @State private var player: AVPlayer? = nil
    @State private var endObserver: NSObjectProtocol? = nil

    private let primary = Color(hexval: "#36796C")

    private var isPostButtonDisabled: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > titleLimit || isPosting
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    videoSection         // ← Apple banner ظاهر من البداية
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
        .disabled(isPosting)
        .overlay(
            ZStack {
                if isPosting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            }
        )
        .alert("Error", isPresented: .constant(postingError != nil)) {
            Button("OK") { postingError = nil }
        } message: { Text(postingError ?? "Unknown error occurred") }
        .onChange(of: title) { _, newVal in
            if newVal.count > titleLimit { title = String(newVal.prefix(titleLimit)) }
        }
        .sheet(isPresented: $showDateSheet) {
            VStack(spacing: 20) {
                Text("Select your birth date")
                    .font(.headline)
                    .padding(.top, 12)

                DatePicker("", selection: $tempSheetDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    Button("Clear") {
                        matchDate = nil
                        showDateSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    Button("Done") {
                        matchDate = tempSheetDate
                        showDateSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(primary)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .presentationDetents([.height(320)])
        }
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
                    isPosting = true
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
                    isPosting = false
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

// MARK: - Compatibility Shim (keeps compiling if your VM still uses caption API)
@MainActor
extension VideoProcessingViewModel {
    func createPost(title: String, isPrivate: Bool, matchDate: Date?) async throws {
        // TODO: Update your ViewModel to persist `title` and `matchDate`.
        try await createPost(caption: title, isPrivate: isPrivate)
    }
}
