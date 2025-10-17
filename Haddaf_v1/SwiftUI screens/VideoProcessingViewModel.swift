import SwiftUI
import PhotosUI
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

@MainActor
class VideoProcessingViewModel: ObservableObject {
    // UI state
    @Published var processingStateMessage = "Preparing video..."
    @Published var isProcessing = false
    @Published var processingComplete = false
    @Published var thumbnail: UIImage?
    @Published var performanceStats: [PFPostStat] = []
    @Published var videoURL: URL?

    // Firebase
    let db = Firestore.firestore()
    let storage = Storage.storage()

    // MARK: - Processing pipeline
    func processVideo(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        let start = Date()

        do {
            processingStateMessage = "Accessing video file..."
            guard let url = await getURL(from: item) else {
                throw NSError(
                    domain: "VideoProcessing",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not retrieve video URL."]
                )
            }
            self.videoURL = url

            // Do thumbnail and (mock) stats in parallel
            async let thumb = generateThumbnail(for: url)
            async let stats = generateMockStatsAfterDelay()

            processingStateMessage = "Generating thumbnail..."
            self.thumbnail = try await thumb

            processingStateMessage = "Analyzing performance..."
            self.performanceStats = await stats

            // Keep spinner visible for at least a few seconds
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 5 {
                try await Task.sleep(nanoseconds: UInt64((5 - elapsed) * 1_000_000_000))
            }

            processingComplete = true
        } catch {
            processingStateMessage = "Error: \(error.localizedDescription)"
            print("processVideo error: \(error)")
        }
    }

    // MARK: - Create post
    func createPost(caption: String, isPrivate: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "Auth",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        guard let localVideoURL = videoURL, let thumb = thumbnail else {
            throw NSError(
                domain: "Upload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing video or thumbnail data."]
            )
        }

        // 1) Upload files
        let postID = UUID().uuidString
        let (videoDL, thumbDL) = try await uploadFiles(
            videoURL: localVideoURL,
            thumbnail: thumb,
            userID: uid,
            postID: postID
        )

        // 2) Author metadata
        let userRef = db.collection("users").document(uid)
        let userDoc = try await userRef.getDocument()
        let data = userDoc.data() ?? [:]
        let first = (data["firstName"] as? String) ?? ""
        let last  = (data["lastName"]  as? String) ?? ""
        let authorUsername = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let profilePic = (data["profilePic"] as? String) ?? ""

        // 3) Create Firestore post document
        let postRef = db.collection("videoPosts").document(postID)
        let postData: [String: Any] = [
            "authorId": userRef,
            "authorUsername": authorUsername,
            "profilePic": profilePic,
            "caption": caption,
            "url": videoDL.absoluteString,
            "thumbnailURL": thumbDL.absoluteString,
            "uploadDateTime": Timestamp(date: Date()),
            "visibility": !isPrivate,   // true = public, false = private
            "likeCount": 0,
            "commentCount": 0
        ]
        try await postRef.setData(postData)

        // 4) Store performance stats (values only) under performanceFeedback/feedback
        let perfRef = postRef.collection("performanceFeedback").document("feedback")
        let perfData: [String: Any]
        if !self.performanceStats.isEmpty {
            // Use actual values from the processing screen
            perfData = [
                "stats": Dictionary(uniqueKeysWithValues: self.performanceStats.map {
                    ($0.label, ["value": $0.value])
                })
            ]
        } else {
            // Fallback placeholder (values only)
            let placeholder: [[String: Any]] = [
                ["label": "GOALS",           "value": 0],
                ["label": "TOTAL ATTEMPTS",  "value": 0],
                ["label": "BLOCKED",         "value": 0],
                ["label": "SHOTS ON TARGET", "value": 0],
                ["label": "CORNERS",         "value": 0],
                ["label": "OFFSIDES",        "value": 0]
            ]
            // Store as a dictionary keyed by label for consistency
            var dict: [String: [String: Any]] = [:]
            for item in placeholder {
                if let label = item["label"] as? String,
                   let value = item["value"] as? Int {
                    dict[label] = ["value": value]
                }
            }
            perfData = ["stats": dict]
        }
        try await perfRef.setData(perfData)

        // 5) Build UI Post object with values only (no max, no normalization)
        let postStats: [PostStat]
        if !self.performanceStats.isEmpty {
            postStats = self.performanceStats.map { s in
                PostStat(label: s.label, value: Double(s.value))
            }
        } else {
            postStats = [
                PostStat(label: "GOALS",           value: 0),
                PostStat(label: "TOTAL ATTEMPTS",  value: 0),
                PostStat(label: "BLOCKED",         value: 0),
                PostStat(label: "SHOTS ON TARGET", value: 0),
                PostStat(label: "CORNERS",         value: 0),
                PostStat(label: "OFFSIDES",        value: 0)
            ]
        }

        // 6) Notify UI with a ready-to-render Post (optimistic UI)
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy HH:mm"
        let newPost = Post(
            id: postID,
            imageName: thumbDL.absoluteString,
            videoURL: videoDL.absoluteString,
            caption: caption,
            timestamp: df.string(from: Date()),
            isPrivate: isPrivate,
            authorName: authorUsername,
            authorImageName: profilePic,
            likeCount: 0,
            commentCount: 0,
            isLikedByUser: false,
            stats: postStats
        )
        NotificationCenter.default.post(
            name: .postCreated,
            object: nil,
            userInfo: ["post": newPost]
        )
    }

    func resetAfterPosting() {
        processingComplete = false
        videoURL = nil
        thumbnail = nil
        performanceStats = []
        processingStateMessage = "Preparing video..."
    }

    // MARK: - Private helpers
    private func getURL(from item: PhotosPickerItem) async -> URL? {
        let r = try? await item.loadTransferable(type: VideoPickerTransferable.self)
        return r?.videoURL
    }

    private func generateThumbnail(for url: URL) async throws -> UIImage {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 60)
        let cgimg = try await gen.image(at: time).image
        return UIImage(cgImage: cgimg)
    }

    private func uploadFiles(
        videoURL: URL,
        thumbnail: UIImage,
        userID: String,
        postID: String
    ) async throws -> (videoURL: URL, thumbnailURL: URL) {
        let videoRef = self.storage.reference().child("posts/\(userID)/\(postID).mov")
        _ = try await videoRef.putFileAsync(from: videoURL)
        let videoDownloadURL = try await videoRef.downloadURL()

        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(
                domain: "Upload",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not compress thumbnail."]
            )
        }
        let thumbRef = self.storage.reference().child("posts/\(userID)/\(postID)_thumb.jpg")
        _ = try await thumbRef.putDataAsync(thumbnailData)
        let thumbnailDownloadURL = try await thumbRef.downloadURL()

        return (videoDownloadURL, thumbnailDownloadURL)
    }

    // Mock generator for the feedback screen (kept as-is; not stored with max in Firestore)
    private func generateMockStatsAfterDelay() async -> [PFPostStat] {
        return [
            .init(label: "GOALS", value: Int.random(in: 0...5), maxValue: 5),
            .init(label: "TOTAL ATTEMPTS", value: Int.random(in: 5...20), maxValue: 20),
            .init(label: "BLOCKED", value: Int.random(in: 0...10), maxValue: 10),
            .init(label: "SHOTS ON TARGET", value: Int.random(in: 1...15), maxValue: 20),
            .init(label: "CORNERS", value: Int.random(in: 0...15), maxValue: 15),
            .init(label: "OFFSIDES", value: Int.random(in: 0...8), maxValue: 10),
        ]
    }
}

struct VideoPickerTransferable: Transferable {
    let videoURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.videoURL)
        } importing: { received in
            let fileName = received.file.lastPathComponent
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(videoURL: copy)
        }
    }
}
