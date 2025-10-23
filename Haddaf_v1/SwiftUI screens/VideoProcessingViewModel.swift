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
    
    // --- PROGRESS PROPERTIES ---
    @Published var progress: Double = 0.0         // For the initial analysis
    @Published var isUploading: Bool = false      // For the final post creation
    @Published var uploadProgress: Double = 0.0 // For the final post creation
    // --- END ---
    
    @Published var thumbnail: UIImage?
    @Published var videoURL: URL?
    @Published var performanceStats: [PFPostStat] = []

    // Firebase
    let db = Firestore.firestore()
    let storage = Storage.storage()

    // MARK: - Processing pipeline
    func processVideo(url: URL, pinpoint: CGPoint) async {
        isProcessing = true
        defer { isProcessing = false }
        
        self.progress = 0.0 // Reset progress
        
        print("Player pinpointed at (x,y): (\(pinpoint.x), \(pinpoint.y))")
        // TODO: Send these coordinates to your AI model here.

        let start = Date()

        do {
            processingStateMessage = "Accessing video file..."
            self.videoURL = url
            self.progress = 0.1 // 10%

            // Do thumbnail and (mock) stats in parallel
            async let thumb = generateThumbnail(for: url)
            async let stats = generateMockStatsAfterDelay()

            processingStateMessage = "Generating thumbnail..."
            self.thumbnail = try await thumb
            self.progress = 0.4 // 40%

            processingStateMessage = "Analyzing performance..."
            self.performanceStats = await stats
            self.progress = 0.8 // 80%

            // Keep spinner visible for at least a few seconds
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 5 {
                // Instead of a dead wait, animate the progress to 100%
                let waitTime = 5 - elapsed
                let steps = 10
                for i in 1...steps {
                    try await Task.sleep(nanoseconds: UInt64((waitTime / Double(steps)) * 1_000_000_000))
                    // Smoothly animate from 0.8 to 1.0
                    self.progress = 0.8 + (0.2 * (Double(i) / Double(steps)))
                }
            } else {
                self.progress = 1.0 // 100%
            }

            processingComplete = true
        } catch {
            processingStateMessage = "Error: \(error.localizedDescription)"
            print("processVideo error: \(error)")
        }
    }

    // MARK: - Create post
    // --- MODIFIED: This function now accepts title and matchDate directly ---
    func createPost(title: String, isPrivate: Bool, matchDate: Date?) async throws {
        self.isUploading = true
        self.uploadProgress = 0.0
        
        guard let uid = Auth.auth().currentUser?.uid else {
            self.isUploading = false
            throw NSError(
                domain: "Auth",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        guard let localVideoURL = videoURL, let thumb = thumbnail else {
            self.isUploading = false
            throw NSError(
                domain: "Upload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing video or thumbnail data."]
            )
        }
        
        self.uploadProgress = 0.1 // Setup complete

        // 1) Upload files
        let postID = UUID().uuidString
        let (videoDL, thumbDL) = try await uploadFiles(
            videoURL: localVideoURL,
            thumbnail: thumb,
            userID: uid,
            postID: postID
        )
        self.uploadProgress = 0.6 // Files uploaded

        // 2) Author metadata
        let userRef = db.collection("users").document(uid)
        let userDoc = try await userRef.getDocument()
        let data = userDoc.data() ?? [:]
        let first = (data["firstName"] as? String) ?? ""
        let last  = (data["lastName"]  as? String) ?? ""
        let authorUsername = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let profilePic = (data["profilePic"] as? String) ?? ""
        self.uploadProgress = 0.7 // Author data fetched

        // 3) Create Firestore post document
        let postRef = db.collection("videoPosts").document(postID)
        var postData: [String: Any] = [
            "authorId": userRef,
            "authorUsername": authorUsername,
            "profilePic": profilePic,
            "caption": title, // Use the 'title' parameter here
            "url": videoDL.absoluteString,
            "thumbnailURL": thumbDL.absoluteString,
            "uploadDateTime": Timestamp(date: Date()),
            "visibility": !isPrivate,  // true = public, false = private
            "likeCount": 0,
            "commentCount": 0
        ]
        
        // Add matchDate if it exists
        if let matchDate = matchDate {
            postData["matchDate"] = Timestamp(date: matchDate)
        }
        
        try await postRef.setData(postData)
        self.uploadProgress = 0.8 // Post document saved

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
        self.uploadProgress = 0.9 // Stats saved

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
            caption: title, // Use 'title' here
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
        
        self.uploadProgress = 1.0 // All done!
        self.isUploading = false
    }

    func resetAfterPosting() {
        processingComplete = false
        videoURL = nil
        thumbnail = nil
        performanceStats = []
        processingStateMessage = "Preparing video..."
        
        // --- RESET NEW PROPERTIES ---
        self.progress = 0.0
        self.isUploading = false
        self.uploadProgress = 0.0
    }

    // MARK: - Private helpers
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

        let videoRef = storage.reference().child("posts/\(userID)/\(postID).mov")
        let thumbRef = storage.reference().child("posts/\(userID)/\(postID)_thumb.jpg")

        let metaVideo = StorageMetadata()
        metaVideo.contentType = "video/mp4"
        let metaThumb = StorageMetadata()
        metaThumb.contentType = "image/jpeg"

        // helper retry func
        func retry<T>(_ task: @escaping () async throws -> T) async throws -> T {
            var attempt = 0
            while true {
                do {
                    return try await task()
                } catch {
                    let nsErr = error as NSError
                    if nsErr.code == -1017, attempt < 3 {
                        attempt += 1
                        print("⚠️ Retry #\(attempt) for Firebase transient error (-1017)")
                        try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * UInt64(attempt)))
                        continue
                    }
                    throw error
                }
            }
        }

        // Upload video (using Data, not file)
        let videoData = try Data(contentsOf: videoURL)
        try await retry {
            _ = try await videoRef.putDataAsync(videoData, metadata: metaVideo)
        }

        // Delay before fetching download URL (Firebase sometimes needs time)
        try await Task.sleep(nanoseconds: 500_000_000)
        let videoDownloadURL = try await retry {
            try await videoRef.downloadURL()
        }

        // Upload thumbnail
        guard let thumbData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Could not compress thumbnail."])
        }
        try await retry {
            _ = try await thumbRef.putDataAsync(thumbData, metadata: metaThumb)
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        let thumbDownloadURL = try await retry {
            try await thumbRef.downloadURL()
        }

        return (videoDownloadURL, thumbDownloadURL)
    }

    private func generateMockStatsAfterDelay() async -> [PFPostStat] {
        [
            .init(label: "GOALS", value: Int.random(in: 0...5), maxValue: 5),
            .init(label: "TOTAL ATTEMPTS", value: Int.random(in: 5...20), maxValue: 20),
            .init(label: "BLOCKED", value: Int.random(in: 0...10), maxValue: 10),
            .init(label: "SHOTS ON TARGET", value: Int.random(in: 1...15), maxValue: 20),
            .init(label: "CORNERS", value: Int.random(in: 0...15), maxValue: 15),
            .init(label: "OFFSIDES", value: Int.random(in: 0...8), maxValue: 10)
        ]
    }
}
