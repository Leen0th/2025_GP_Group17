//
//  ChallengeModule.swift
//  Haddaf_v1
//

import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// =======================================================
// MARK: - Firestore/Storage Paths (Constants)
// =======================================================

enum DBPaths {
    static let challenges  = "challenges"
    static let submissions = "submissions"
    static let ratings     = "ratings"
    static let users       = "users"
}

// Storage: challenges/{challengeId}/submissions/{uid}/{uuid}.mp4
func submissionStoragePath(challengeId: String, uid: String) -> String {
    "challenges/\(challengeId)/submissions/\(uid)/\(UUID().uuidString).mp4"
}

// =======================================================
// MARK: - Models
// =======================================================

struct AppChallenge: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let criteria: [String]
    let imageURL: String
    let startAt: Date
    let endAt: Date

    var isPast: Bool { Date() >= endAt }
    var statusText: String { isPast ? "Past" : "New" }

    var dateText: String {
        if isPast {
            return "Ended on \(endAt.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "End by \(endAt.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

struct ChallengeSubmission: Identifiable, Hashable {
    let id: String
    let uid: String
    let videoURL: String
    let storagePath: String
    let createdAt: Date
    let durationSec: Double
    let totalStars: Int
    let totalPoints: Int
    let ratingCount: Int
}

struct UserMini: Identifiable, Hashable {
    let id: String
    let fullName: String
    let photoURL: String
}

// =======================================================
// MARK: - Services: Challenges (Realtime)
// =======================================================

final class ChallengeService: ObservableObject {
    @Published var challenges: [AppChallenge] = []
    @Published var loading = true
    @Published var errorText: String?

    private var listener: ListenerRegistration?

    func start() {
        listener?.remove()
        loading = true
        errorText = nil

        listener = Firestore.firestore()
            .collection(DBPaths.challenges)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    self.loading = false
                    self.errorText = err.localizedDescription
                    return
                }
                guard let snap else {
                    self.loading = false
                    self.challenges = []
                    return
                }

                self.challenges = snap.documents.compactMap { d in
                    let data = d.data()
                    let title = data["title"] as? String ?? ""
                    let desc = data["description"] as? String ?? ""
                    let criteria = data["criteria"] as? [String] ?? []
                    let imageURL = data["imageURL"] as? String ?? ""

                    let startAt = (data["startAt"] as? Timestamp)?.dateValue() ?? Date()
                    let endAt   = (data["endAt"] as? Timestamp)?.dateValue() ?? Date()

                    return AppChallenge(
                        id: d.documentID,
                        title: title,
                        description: desc,
                        criteria: criteria,
                        imageURL: imageURL,
                        startAt: startAt,
                        endAt: endAt
                    )
                }

                self.loading = false
            }
    }

    deinit { listener?.remove() }
}

// =======================================================
// MARK: - Services: Submissions (Realtime)
// =======================================================

final class SubmissionService: ObservableObject {
    @Published var submissions: [ChallengeSubmission] = []   // Most recent
    @Published var top3: [ChallengeSubmission] = []          // Highest points
    @Published var loading = true
    @Published var errorText: String?

    private var listenerAll: ListenerRegistration?
    private var listenerTop: ListenerRegistration?

    func stop() {
        listenerAll?.remove()
        listenerTop?.remove()
        listenerAll = nil
        listenerTop = nil
    }

    func listenAll(challengeId: String) {
        listenerAll?.remove()
        loading = true
        errorText = nil

        listenerAll = Firestore.firestore()
            .collection(DBPaths.challenges).document(challengeId)
            .collection(DBPaths.submissions)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }

                if let err {
                    self.loading = false
                    self.errorText = err.localizedDescription
                    return
                }
                guard let snap else {
                    self.loading = false
                    self.submissions = []
                    return
                }

                self.submissions = snap.documents.compactMap { d in
                    self.parseSubmission(doc: d)
                }

                self.loading = false
            }
    }

    func listenTop3(challengeId: String) {
        listenerTop?.remove()

        listenerTop = Firestore.firestore()
            .collection(DBPaths.challenges)
            .document(challengeId)
            .collection(DBPaths.submissions)
            // Only sort by totalPoints in Firestore (no composite index needed)
            .order(by: "totalPoints", descending: true)
            // Fetch top 20 to ensure we get all tied scores
            .limit(to: 20)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }

                if let err {
                    self.errorText = err.localizedDescription
                    return
                }
                guard let snap else {
                    self.top3 = []
                    return
                }

                // Parse all submissions
                let allSubmissions = snap.documents.compactMap { d in
                    self.parseSubmission(doc: d)
                }
                
                // Sort manually in code:
                // 1) Higher points first
                // 2) If points are equal, earlier submission wins
                self.top3 = allSubmissions.sorted { first, second in
                    // If points are different, higher points come first
                    if first.totalPoints != second.totalPoints {
                        return first.totalPoints > second.totalPoints
                    }
                    // If points are equal, earlier date comes first
                    return first.createdAt < second.createdAt
                }
                .prefix(3)  // Take only top 3
                .map { $0 } // Convert to Array
            }
    }



    private func parseSubmission(doc: QueryDocumentSnapshot) -> ChallengeSubmission? {
        let data = doc.data()

        let uid = data["uid"] as? String ?? ""
        let videoURL = data["videoURL"] as? String ?? ""
        let storagePath = data["storagePath"] as? String ?? ""

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let durationSec = data["durationSec"] as? Double ?? 0
        let totalStars = data["totalStars"] as? Int ?? 0
        let totalPoints = data["totalPoints"] as? Int ?? 0
        let ratingCount = data["ratingCount"] as? Int ?? 0

        return ChallengeSubmission(
            id: doc.documentID,
            uid: uid,
            videoURL: videoURL,
            storagePath: storagePath,
            createdAt: createdAt,
            durationSec: durationSec,
            totalStars: totalStars,
            totalPoints: totalPoints,
            ratingCount: ratingCount
        )
    }

    deinit { stop() }
}

// =======================================================
// MARK: - User Service (Cache + Fetch users/{uid})
// =======================================================

@MainActor
final class UserService: ObservableObject {
    static let shared = UserService()

    private var cache: [String: UserMini] = [:]
    private var inFlight: Set<String> = []

    func getCached(uid: String) -> UserMini? { cache[uid] }

    func fetchUser(uid: String) async -> UserMini? {
        if let cached = cache[uid] { return cached }
        if inFlight.contains(uid) { return cache[uid] }

        inFlight.insert(uid)
        defer { inFlight.remove(uid) }

        do {
            let snap = try await Firestore.firestore()
                .collection(DBPaths.users)
                .document(uid)
                .getDocument()

            guard let data = snap.data() else { return nil }

            let firstName = data["firstName"] as? String ?? ""
            let lastName  = data["lastName"] as? String ?? ""

            let composed = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            let fullName = composed.isEmpty ? "Player" : composed

            let photoURL = data["profilePic"] as? String ?? ""

            let user = UserMini(id: uid, fullName: fullName, photoURL: photoURL)
            cache[uid] = user
            return user
        } catch {
            return nil
        }
    }
}

// =======================================================
// MARK: - Role Resolver (from Firestore users/{uid})
// =======================================================

@MainActor
final class RoleResolver: ObservableObject {
    @Published var role: String = "Player"

    func loadRoleIfPossible() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            role = "Guest"
            return
        }

        do {
            let snap = try await Firestore.firestore()
                .collection(DBPaths.users)
                .document(uid)
                .getDocument()

            let data = snap.data() ?? [:]

            // Adjust if your field name is different
            let raw = (data["role"] as? String)
            ?? (data["userRole"] as? String)
            ?? (data["type"] as? String)
            ?? "Player"

            role = raw
        } catch {
            role = "Player"
        }
    }

    var isPlayer: Bool { role.lowercased() == "player" }
    var isCoach: Bool { role.lowercased() == "coach" }
}

// =======================================================
// MARK: - Rating (Transaction-safe) - one time only
// =======================================================

enum RatingError: LocalizedError {
    case alreadyRated
    var errorDescription: String? { "You already evaluated this player." }
}

// Returns (updatedTotalStars, updatedRatingCount)
func rateSubmissionOnce(challengeId: String, submissionId: String, stars: Int) async throws -> (Int, Int) {
    guard (1...5).contains(stars) else { throw NSError(domain: "rating", code: 0) }
    guard let raterUid = Auth.auth().currentUser?.uid else { throw NSError(domain: "auth", code: 401) }

    let db = Firestore.firestore()
    let subRef = db.collection(DBPaths.challenges).document(challengeId)
        .collection(DBPaths.submissions).document(submissionId)

    let ratingRef = subRef.collection(DBPaths.ratings).document(raterUid)

    let result = try await db.runTransaction { txn, errPointer -> Any? in
        do {
            let oldSnap = try txn.getDocument(ratingRef)
            if oldSnap.exists {
                errPointer?.pointee = RatingError.alreadyRated as NSError
                return nil
            }

            let subSnap = try txn.getDocument(subRef)
            let totalStars  = (subSnap.data()?["totalStars"] as? Int) ?? 0
            let ratingCount = (subSnap.data()?["ratingCount"] as? Int) ?? 0

            let updatedCount = ratingCount + 1
            let updatedTotalStars = totalStars + stars

            // Each star = 5 points, total points = totalStars * 5
            let updatedPoints = updatedTotalStars * 5

            txn.setData([
                "stars": stars,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: ratingRef)

            txn.updateData([
                "totalStars": updatedTotalStars,
                "ratingCount": updatedCount,
                "totalPoints": updatedPoints
            ], forDocument: subRef)

            return ["totalStars": updatedTotalStars, "ratingCount": updatedCount]
        } catch {
            errPointer?.pointee = error as NSError
            return nil
        }
    }

    let dict = result as? [String: Any]
    let ts = dict?["totalStars"] as? Int ?? 0
    let rc = dict?["ratingCount"] as? Int ?? 0
    return (ts, rc)
}

// =======================================================
// MARK: - Upload / Delete Controller
// =======================================================

@MainActor
final class ChallengeUploader: ObservableObject {
    @Published var busy = false
    @Published var showTooLongAlert = false
    @Published var errorText: String?

    func uploadPickedVideo(item: PhotosPickerItem, challengeId: String, endAt: Date) async {
        guard Date() < endAt else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        busy = true
        errorText = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "video", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to load video"])
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            try data.write(to: tempURL)

            let asset = AVAsset(url: tempURL)
            let seconds = CMTimeGetSeconds(asset.duration)

            if seconds > 30.0 {
                busy = false
                showTooLongAlert = true
                return
            }

            // Upload to Storage
            let storagePath = submissionStoragePath(challengeId: challengeId, uid: uid)
            let ref = Storage.storage().reference().child(storagePath)

            let meta = StorageMetadata()
            meta.contentType = "video/mp4"

            _ = try await ref.putDataAsync(data, metadata: meta)
            let url = try await ref.downloadURL()

            // Create Firestore submission
            let subData: [String: Any] = [
                "uid": uid,
                "videoURL": url.absoluteString,
                "storagePath": storagePath,
                "createdAt": FieldValue.serverTimestamp(),
                "durationSec": seconds,
                "totalStars": 0,
                "totalPoints": 0,
                "ratingCount": 0
            ]

            _ = try await Firestore.firestore()
                .collection(DBPaths.challenges).document(challengeId)
                .collection(DBPaths.submissions)
                .addDocument(data: subData)

            busy = false
        } catch {
            busy = false
            errorText = error.localizedDescription
        }
    }

    func deleteSubmission(challengeId: String, submission: ChallengeSubmission) async throws {
        guard let currentUid = Auth.auth().currentUser?.uid else { return }
        guard currentUid == submission.uid else { return }

        let db = Firestore.firestore()
        let subRef = db.collection(DBPaths.challenges).document(challengeId)
            .collection(DBPaths.submissions).document(submission.id)

        // Delete Storage file first (best effort)
        if !submission.storagePath.isEmpty {
            try await Storage.storage().reference().child(submission.storagePath).delete()
        }

        // Delete Firestore doc
        try await subRef.delete()
    }
}

// =======================================================
// MARK: - Video Thumbnail Generator (Local Preview Frame)
// =======================================================

@MainActor
final class VideoThumbnailCache: ObservableObject {
    static let shared = VideoThumbnailCache()
    private var cache: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    func cached(for url: String) -> UIImage? { cache[url] }

    func generate(urlString: String) async -> UIImage? {
        if let img = cache[urlString] { return img }
        if inFlight.contains(urlString) { return cache[urlString] }

        inFlight.insert(urlString)
        defer { inFlight.remove(urlString) }

        guard let url = URL(string: urlString) else { return nil }

        do {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let ui = UIImage(cgImage: cgImage)
            cache[urlString] = ui
            return ui
        } catch {
            return nil
        }
    }
}

private struct VideoThumbnailView: View {
    let urlString: String

    @State private var image: UIImage?
    @State private var loading = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.systemGray6))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 210)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if loading {
                ProgressView()
            } else {
                LinearGradient(
                    colors: [.black.opacity(0.12), .black.opacity(0.24)],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
        }
        .frame(height: 210)
        .task {
            loading = true
            if let cached = VideoThumbnailCache.shared.cached(for: urlString) {
                image = cached
                loading = false
                return
            }
            image = await VideoThumbnailCache.shared.generate(urlString: urlString)
            loading = false
        }
    }
}

// =======================================================
// MARK: - Popup (Full-screen dim + smaller card)
// =======================================================

private struct ActionRequiredPopup: View {
    @Binding var isPresented: Bool

    let title: String
    let message: String
    let buttonTitle: String

    var body: some View {
        ZStack {
            // Full-screen dim
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut) { isPresented = false }
                }

            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(BrandColors.darkTeal)

                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                Button {
                    withAnimation(.easeInOut) { isPresented = false }
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BrandColors.darkTeal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: 320) // ✅ smaller popup
            .background(BrandColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// =======================================================
// MARK: - Challenge List Screen
// =======================================================

struct ChallengeView: View {
    private let accent = BrandColors.darkTeal
    @StateObject private var service = ChallengeService()

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Text("Challenges")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundColor(accent)
                            .padding(.top, 10)

                        if service.loading {
                            ProgressView().tint(accent).padding(.top, 30)
                        } else if let err = service.errorText {
                            Text(err)
                                .foregroundColor(.red)
                                .font(.system(size: 13, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                        } else if service.challenges.isEmpty {
                            Text("No challenges yet.")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14, design: .rounded))
                                .padding(.top, 20)
                        } else {
                            ForEach(service.challenges) { ch in
                                NavigationLink {
                                    if ch.isPast {
                                        PastChallengePage(challenge: ch)
                                    } else {
                                        NewChallengePage(challenge: ch)
                                    }
                                } label: {
                                    ChallengeListCard(challenge: ch, accent: accent)
                                        .opacity(ch.isPast ? 0.45 : 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { service.start() }
    }
}

private struct ChallengeListCard: View {
    let challenge: AppChallenge
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = URL(string: challenge.imageURL), !challenge.imageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .empty: RoundedRectangle(cornerRadius: 18).fill(BrandColors.lightGray.opacity(0.35))
                        default: RoundedRectangle(cornerRadius: 18).fill(BrandColors.lightGray.opacity(0.35))
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(BrandColors.lightGray.opacity(0.35))
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.10), .black.opacity(0.26)],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(challenge.title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(challenge.statusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(challenge.isPast ? .gray : accent)

                Text(challenge.dateText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(10)
        }
        .contentShape(Rectangle())
    }
}

// =======================================================
// MARK: - New Challenge Page
// =======================================================

struct NewChallengePage: View {
    let challenge: AppChallenge
    private let accent = BrandColors.darkTeal

    @EnvironmentObject private var session: AppSession

    @StateObject private var subService = SubmissionService()
    @StateObject private var uploader = ChallengeUploader()
    @StateObject private var roleResolver = RoleResolver()

    @State private var pickedItem: PhotosPickerItem?
    @State private var showPicker = false

    // ✅ Full-screen popup state (so dim covers whole screen)
    @State private var showActionPopup = false
    @State private var actionPopupMessage = ""

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Text("New Challenge")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                        .padding(.top, 8)

                    ChallengeInfoCard(
                        challenge: challenge,
                        showUploadButton: true,
                        onUploadTap: { handleUploadTap() },
                        uploading: uploader.busy
                    )
                    .padding(.horizontal, 14)

                    HStack {
                        Text("Posts")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)

                    if let err = uploader.errorText {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.system(size: 12, design: .rounded))
                            .padding(.horizontal, 22)
                    }

                    if subService.loading {
                        ProgressView().tint(accent).padding(.top, 8)
                    } else if let err = subService.errorText {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .padding(.horizontal, 18)
                    } else {
                        let pinned = pinnedOrderedPosts(top3: subService.top3, all: subService.submissions)

                        if pinned.isEmpty {
                            Text("No posts yet.")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14, design: .rounded))
                                .padding(.top, 8)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(pinned) { sub in
                                    SubmissionCard(
                                        challengeId: challenge.id,
                                        submission: sub,
                                        pinnedRank: pinnedRankFor(subId: sub.id, top3: subService.top3),
                                        isPlayer: roleResolver.isPlayer,
                                        isCoach: roleResolver.isCoach,
                                        onActionNotAllowed: { msg in
                                            presentActionPopup(msg)
                                        }
                                    )
                                    .padding(.horizontal, 14)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 18)
                }
                .padding(.bottom, 20)
            }

            // ✅ Full-screen popup overlay
            if showActionPopup {
                ActionRequiredPopup(
                    isPresented: $showActionPopup,
                    title: "Join Haddaf!",
                    message: actionPopupMessage,
                    buttonTitle: "Got It"
                )
                .zIndex(999)
            }
        }
        .onAppear {
            subService.listenAll(challengeId: challenge.id)
            subService.listenTop3(challengeId: challenge.id)
            Task { await roleResolver.loadRoleIfPossible() }
        }
        .onDisappear { subService.stop() }

        .photosPicker(isPresented: $showPicker, selection: $pickedItem, matching: .videos)

        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploader.uploadPickedVideo(item: newItem, challengeId: challenge.id, endAt: challenge.endAt) }
        }

        .alert("Video too long", isPresented: $uploader.showTooLongAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Video must be 30 seconds or less.")
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presentActionPopup(_ message: String) {
        actionPopupMessage = message
        withAnimation(.easeInOut) { showActionPopup = true }
    }

    private func handleUploadTap() {
        // Guest OR Coach -> same popup style + same dim
        if session.isGuest || roleResolver.isCoach || !roleResolver.isPlayer {
            presentActionPopup("You must be signed in and be a player to perform this action.")
            return
        }

        // Player -> open picker
        showPicker = true
    }

    private func pinnedOrderedPosts(top3: [ChallengeSubmission], all: [ChallengeSubmission]) -> [ChallengeSubmission] {
        let topIds = Set(top3.map { $0.id })
        let rest = all.filter { !topIds.contains($0.id) }
        return top3 + rest
    }

    private func pinnedRankFor(subId: String, top3: [ChallengeSubmission]) -> Int? {
        if let idx = top3.firstIndex(where: { $0.id == subId }) { return idx + 1 }
        return nil
    }
}

// =======================================================
// MARK: - Past Challenge Page
// =======================================================

struct PastChallengePage: View {
    let challenge: AppChallenge
    private let accent = BrandColors.darkTeal

    @EnvironmentObject private var session: AppSession

    @StateObject private var subService = SubmissionService()
    @StateObject private var roleResolver = RoleResolver()

    // ✅ Full-screen popup state here too (stars tap in past page)
    @State private var showActionPopup = false
    @State private var actionPopupMessage = ""

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Text("Past Challenge")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                        .padding(.top, 8)

                    ChallengeInfoCard(
                        challenge: challenge,
                        showUploadButton: false,
                        onUploadTap: nil,
                        uploading: false
                    )
                    .padding(.horizontal, 14)

                    HStack {
                        Text("Winner Posts")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)

                    if subService.top3.isEmpty {
                        Text("—")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(subService.top3.enumerated()), id: \.element.id) { index, submission in
                                SubmissionCard(
                                    challengeId: challenge.id,
                                    submission: submission,
                                    // Show ranking badge on profile image (1st, 2nd, 3rd)
                                    pinnedRank: index + 1,
                                    isPlayer: roleResolver.isPlayer,
                                    isCoach: roleResolver.isCoach,
                                    onActionNotAllowed: { msg in
                                        presentActionPopup(msg)
                                    }
                                )
                                .padding(.horizontal, 14)
                            }

                        }
                    }

                    Spacer(minLength: 18)
                }
                .padding(.bottom, 20)
            }

            if showActionPopup {
                ActionRequiredPopup(
                    isPresented: $showActionPopup,
                    title: "Join Haddaf!",
                    message: actionPopupMessage,
                    buttonTitle: "Got It"
                )
                .zIndex(999)
            }
        }
        .onAppear {
            subService.listenTop3(challengeId: challenge.id)
            Task { await roleResolver.loadRoleIfPossible() }
        }
        .onDisappear { subService.stop() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presentActionPopup(_ message: String) {
        actionPopupMessage = message
        withAnimation(.easeInOut) { showActionPopup = true }
    }
}

// =======================================================
// MARK: - Shared Challenge Info Card
// =======================================================

private struct ChallengeInfoCard: View {
    let challenge: AppChallenge
    let showUploadButton: Bool
    let onUploadTap: (() -> Void)?
    let uploading: Bool

    @State private var showEvalInfo = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let url = URL(string: challenge.imageURL), !challenge.imageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .empty:
                            fallbackHeader
                        default:
                            fallbackHeader
                        }
                    }
                } else {
                    fallbackHeader
                }
            }
            .frame(height: 155)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(14)
            .padding(.bottom, -4)

            VStack(alignment: .leading, spacing: 14) {
                Text("Description")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text(challenge.description.isEmpty ? "—" : challenge.description)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)

                Divider().opacity(0.5)

                HStack(spacing: 6) {
                    Text("Evaluation Criteria")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    Button { showEvalInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .alert("Evaluation Method", isPresented: $showEvalInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Rating is based on stars. Each star equals 5 points.")
                }

                let cols = [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ]

                LazyVGrid(columns: cols, alignment: .leading, spacing: 14) {
                    if challenge.criteria.isEmpty {
                        CriteriaDot(text: "Shooting accuracy")
                        CriteriaDot(text: "Decision making")
                        CriteriaDot(text: "Ball control")
                        CriteriaDot(text: "Consistency")
                    } else {
                        ForEach(challenge.criteria, id: \.self) { c in
                            CriteriaDot(text: c)
                        }
                    }
                }
                .padding(.top, 2)

                if showUploadButton, let onUploadTap {
                    HStack {
                        Spacer()
                        Button {
                            onUploadTap()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(uploading ? "Uploading..." : "Upload Challenge")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(BrandColors.darkTeal)
                            .clipShape(Capsule())
                            .shadow(color: BrandColors.darkTeal.opacity(0.18), radius: 8, x: 0, y: 6)
                            .opacity(uploading ? 0.7 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(uploading)
                        Spacer()
                    }
                    .padding(.top, 10)
                }
            }
            .padding(16)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
    }

    private var fallbackHeader: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandColors.lightGray.opacity(0.35))

            LinearGradient(
                colors: [.black.opacity(0.18), .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(challenge.title)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
        }
    }
}

private struct CriteriaDot: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(BrandColors.darkTeal)
                .frame(width: 9, height: 9)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

// =======================================================
// MARK: - Submission Card (Pinned top3 + recent)
// =======================================================

private struct SubmissionCard: View {
    let challengeId: String
    let submission: ChallengeSubmission
    let pinnedRank: Int?

    let isPlayer: Bool
    let isCoach: Bool

    // ✅ IMPORTANT: to show popup at page-level (full-screen dim)
    let onActionNotAllowed: (String) -> Void

    @EnvironmentObject private var session: AppSession

    @StateObject private var uploader = ChallengeUploader()

    // User info
    @State private var user: UserMini?

    // Video sheet
    @State private var showPlayer = false

    // Rating state
    @State private var selectedStars: Int = 0
    @State private var isEvaluated: Bool = false
    @State private var busy = false
    @State private var errorText: String?

    // After evaluation
    @State private var currentPoints: Int = 0

    // Delete
    @State private var showDeleteConfirm = false
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 12) {

            // Header: avatar + name + date + pinned rank
            HStack(spacing: 12) {

                // ✅ Tap profile -> PlayerProfileContentView
                NavigationLink {
                    // If your PlayerProfileContentView has a different initializer,
                    // adjust this line only.
                    PlayerProfileContentView(userID: submission.uid)
                        .environmentObject(session)
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            UserAvatar(
                                photoURL: user?.photoURL ?? "",
                                fallbackText: initials(user?.fullName ?? "Player")
                            )
                            .frame(width: 52, height: 52)

                            if let pinnedRank {
                                RankBadge(rank: pinnedRank)
                                    .offset(x: -8, y: -10)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(user?.fullName ?? "Player")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))

                            Text(submission.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Delete for owner only (player, not guest)
                if canDelete {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: deleting ? "hourglass" : "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(deleting)
                }
            }

            // Video thumbnail
            Button { showPlayer = true } label: {
                VideoThumbnailView(urlString: submission.videoURL)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPlayer) {
                VideoSheet(urlString: submission.videoURL)
            }

            // Rating row OR points row
            if !isEvaluated {
                HStack(spacing: 10) {
                    StarPicker(
                        selected: $selectedStars,
                        locked: busy,
                        canInteract: canEvaluate,
                        onBlockedTap: {
                            onActionNotAllowed("You must be signed in and be a player to perform this action.")
                        }
                    )

                    Spacer()

                    Button {
                        Task { await evaluateNow() }
                    } label: {
                        Text(busy ? "Evaluating..." : "Evaluate")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(BrandColors.darkTeal)
                            .clipShape(Capsule())
                            .opacity((selectedStars == 0 || busy) ? 0.45 : 1)
                    }
                    .disabled(selectedStars == 0 || busy)
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.yellow)

                    Text("\(currentPoints) pts")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Spacer()
                }
                .padding(.top, 2)
            }

            if let errorText {
                Text(errorText)
                    .foregroundColor(.red)
                    .font(.system(size: 12, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        .task {
            await loadUser()
            await checkIfAlreadyRated()
            currentPoints = submission.totalPoints
        }
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deleteNow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var canDelete: Bool {
        guard !session.isGuest else { return false }
        guard isPlayer, !isCoach else { return false }
        guard let currentUid = Auth.auth().currentUser?.uid else { return false }
        return currentUid == submission.uid
    }

    private var canEvaluate: Bool {
        if session.isGuest { return false }
        if isCoach { return false }
        if !isPlayer { return false }
        return true
    }

    private func loadUser() async {
        if let cached = UserService.shared.getCached(uid: submission.uid) {
            user = cached
            return
        }
        user = await UserService.shared.fetchUser(uid: submission.uid)
    }

    private func evaluateNow() async {
        // Guest/Coach -> popup
        if !canEvaluate {
            onActionNotAllowed("You must be signed in and be a player to perform this action.")
            return
        }

        guard selectedStars > 0 else { return }

        busy = true
        errorText = nil

        do {
            let (updatedTotalStars, _) = try await rateSubmissionOnce(
                challengeId: challengeId,
                submissionId: submission.id,
                stars: selectedStars
            )

            currentPoints = updatedTotalStars * 5
            isEvaluated = true
            busy = false
        } catch {
            busy = false
            errorText = error.localizedDescription
        }
    }

    private func checkIfAlreadyRated() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let ratingDoc = try await Firestore.firestore()
                .collection(DBPaths.challenges).document(challengeId)
                .collection(DBPaths.submissions).document(submission.id)
                .collection(DBPaths.ratings).document(uid)
                .getDocument()

            if ratingDoc.exists {
                isEvaluated = true
            }
        } catch { }
    }

    private func deleteNow() async {
        deleting = true
        errorText = nil
        do {
            try await uploader.deleteSubmission(challengeId: challengeId, submission: submission)
            deleting = false
        } catch {
            deleting = false
            errorText = error.localizedDescription
        }
    }

    private func initials(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }
}

// =======================================================
// MARK: - User Avatar
// =======================================================

private struct UserAvatar: View {
    let photoURL: String
    let fallbackText: String

    var body: some View {
        ZStack {
            Circle().fill(Color(UIColor.systemGray6))

            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .empty:
                        Text(fallbackText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(BrandColors.darkTeal)
                    default:
                        Text(fallbackText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(BrandColors.darkTeal)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(fallbackText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkTeal)
            }
        }
        .clipShape(Circle())
    }
}

// =======================================================
// MARK: - Stars Picker (Blocks guest/coach)
// =======================================================

private struct StarPicker: View {
    @Binding var selected: Int
    let locked: Bool

    let canInteract: Bool
    let onBlockedTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    guard !locked else { return }
                    guard canInteract else { onBlockedTap(); return }
                    selected = i
                } label: {
                    Image(systemName: i <= selected ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(i <= selected ? .yellow : .gray.opacity(0.55))
                        .opacity(locked ? 0.7 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// =======================================================
// MARK: - Video Player Sheet
// =======================================================

private struct VideoSheet: View {
    let urlString: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let url = URL(string: urlString) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .ignoresSafeArea()
                } else {
                    Text("Invalid video URL")
                        .foregroundColor(.white)
                }
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// =======================================================
// MARK: - Rank Badge
// =======================================================

private struct RankBadge: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(rank == 1 ? Color.yellow : (rank == 2 ? Color(UIColor.systemGray3) : Color.orange))
                .frame(width: 22, height: 22)

            Text("\(rank)")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(.black.opacity(0.75))
        }
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}
