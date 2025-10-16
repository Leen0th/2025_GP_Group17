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
    let storage = Storage.storage() // ← make storage available in scope

    // MARK: - Processing pipeline
    func processVideo(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        let start = Date()

        do {
            processingStateMessage = "Accessing video file..."
            guard let url = await getURL(from: item) else {
                throw NSError(domain: "VideoProcessing", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not retrieve video URL."])
            }
            self.videoURL = url

            async let thumb = generateThumbnail(for: url)
            async let stats = generateMockStatsAfterDelay()

            processingStateMessage = "Generating thumbnail..."
            self.thumbnail = try await thumb

            processingStateMessage = "Analyzing performance..."
            self.performanceStats = await stats

            // keep spinner at least ~5s for UX
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 5 { try await Task.sleep(nanoseconds: UInt64((5 - elapsed) * 1_000_000_000)) }

            processingComplete = true
        } catch {
            processingStateMessage = "Error: \(error.localizedDescription)"
            print("processVideo error: \(error)")
        }
    }

    // MARK: - Create post
    func createPost(caption: String, isPrivate: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        guard let localVideoURL = videoURL, let thumb = thumbnail else {
            throw NSError(domain: "Upload", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing video or thumbnail data."])
        }

        let postID = UUID().uuidString
        let (videoDL, thumbDL) = try await uploadFiles(videoURL: localVideoURL,
                                                       thumbnail: thumb,
                                                       userID: uid,
                                                       postID: postID)

        // author info
        let userRef = db.collection("users").document(uid)
        let userDoc = try await userRef.getDocument()
        let data = userDoc.data() ?? [:]
        let first = (data["firstName"] as? String) ?? ""
        let last  = (data["lastName"]  as? String) ?? ""
        let authorUsername = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let profilePic = (data["profilePic"] as? String) ?? ""

        // post document
        let postRef = db.collection("videoPosts").document(postID)
        let postData: [String: Any] = [
            "authorId": userRef,                           // DocumentReference
            "authorUsername": authorUsername,
            "profilePic": profilePic,
            "caption": caption,
            "url": videoDL.absoluteString,
            "thumbnailURL": thumbDL.absoluteString,
            "uploadDateTime": Timestamp(date: Date()),
            "visibility": !isPrivate,                      // true = public
            "likeCount": 0,
            "commentCount": 0
        ]
        try await postRef.setData(postData)

        // performance feedback (optional)
        let perfRef = postRef.collection("performanceFeedback").document("feedback")
        let perf: [String: Any] = [
            "passingAccuracy": performanceStats.first { $0.label == "PASSING ACCURACY" }?.value ?? 0,
            "speed": performanceStats.first { $0.label == "SPEED" }?.value ?? 0,
            "score": performanceStats.first { $0.label == "SCORE" }?.value ?? 0
        ]
        try await perfRef.setData(perf)

        // notify UI to insert immediately
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
            stats: nil
        )
        NotificationCenter.default.post(name: .postCreated, object: nil, userInfo: ["post": newPost])
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

    private func uploadFiles(videoURL: URL,
                             thumbnail: UIImage,
                             userID: String,
                             postID: String) async throws -> (videoURL: URL, thumbnailURL: URL) {
        // video
        let videoRef = self.storage.reference().child("posts/\(userID)/\(postID).mov")
        _ = try await videoRef.putFileAsync(from: videoURL)
        let videoDownloadURL = try await videoRef.downloadURL()

        // thumbnail
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not compress thumbnail."])
        }
        let thumbRef = self.storage.reference().child("posts/\(userID)/\(postID)_thumb.jpg")
        _ = try await thumbRef.putDataAsync(thumbnailData)
        let thumbnailDownloadURL = try await thumbRef.downloadURL()

        return (videoDownloadURL, thumbnailDownloadURL)
    }

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

// Transferable used to safely obtain a file URL from PhotosPicker (no memory blowups)

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
