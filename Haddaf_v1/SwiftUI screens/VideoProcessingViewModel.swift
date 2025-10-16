import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import AVFoundation

@MainActor
class VideoProcessingViewModel: ObservableObject {
    @Published var processingStateMessage = "Preparing video..."
    @Published var isProcessing = false
    @Published var processingComplete = false
    @Published var thumbnail: UIImage?
    @Published var performanceStats: [PFPostStat] = []
    @Published var videoURL: URL?

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    func processVideo(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        let startTime = Date()

        do {
            processingStateMessage = "Accessing video file..."
            // This now uses the memory-safe getURL function
            guard let url = await getURL(from: item) else {
                throw NSError(domain: "VideoProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve video URL."])
            }
            self.videoURL = url

            async let generatedThumbnail = generateThumbnail(for: url)
            async let mockStats = generateMockStatsAfterDelay()

            processingStateMessage = "Generating thumbnail..."
            self.thumbnail = try await generatedThumbnail

            processingStateMessage = "Analyzing performance..."
            self.performanceStats = await mockStats

            let elapsedTime = Date().timeIntervalSince(startTime)
            if elapsedTime < 5.0 {
                let remainingTime = 5.0 - elapsedTime
                try await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
            }

            processingComplete = true

        } catch {
            processingStateMessage = "Error: \(error.localizedDescription)"
            print("Video processing failed: \(error)")
        }
    }

    func createPost(caption: String, isPrivate: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]) }
        guard let localVideoURL = videoURL, let thumbnailImage = thumbnail else { throw NSError(domain: "Upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing video or thumbnail data."]) }

        let postID = UUID().uuidString
        let (videoDownloadURL, thumbnailDownloadURL) = try await uploadFiles(videoURL: localVideoURL, thumbnail: thumbnailImage, userID: uid, postID: postID)
        let userDocRef = db.collection("users").document(uid)
        let userDoc = try await userDocRef.getDocument()

        let userData = userDoc.data()
        let firstName = userData?["firstName"] as? String ?? ""
        let lastName = userData?["lastName"] as? String ?? ""
        let authorUsername = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        let authorProfilePic = userData?["profilePic"] as? String ?? ""

        let postData: [String: Any] = [
            "authorId": userDocRef,
            "authorUsername": authorUsername,
            "profilePic": authorProfilePic,
            "caption": caption,
            "url": videoDownloadURL.absoluteString,
            "thumbnailURL": thumbnailDownloadURL.absoluteString,
            "uploadDateTime": Timestamp(date: Date()),
            "visibility": !isPrivate,
            "likeCount": 0,
            "commentCount": 0
        ]

        let postRef = db.collection("videoPosts").document(postID)
        try await postRef.setData(postData)

        let feedbackRef = postRef.collection("performanceFeedback").document("feedback")
        let performanceData: [String: Any] = [
            "passingAccuracy": performanceStats.first { $0.label == "PASSING ACCURACY" }?.value ?? 0,
            "speed": performanceStats.first { $0.label == "SPEED" }?.value ?? 0,
            "score": performanceStats.first { $0.label == "SCORE" }?.value ?? 0
        ]
        try await feedbackRef.setData(performanceData)
    }

    // MARK: - Private Helper Methods

    // ✅ This function copies the file directly without loading it into RAM.
    private func getURL(from item: PhotosPickerItem) async -> URL? {
        let results = try? await item.loadTransferable(type: VideoPickerTransferable.self)
        return results?.videoURL
    }

    private func generateThumbnail(for url: URL) async throws -> UIImage {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 60)
        let cgImage = try await imageGenerator.image(at: time).image
        return UIImage(cgImage: cgImage)
    }

    private func uploadFiles(videoURL: URL, thumbnail: UIImage, userID: String, postID: String) async throws -> (videoURL: URL, thumbnailURL: URL) {
        let videoRef = storage.reference().child("posts/\(userID)/\(postID).mov")
        _ = try await videoRef.putFileAsync(from: videoURL)
        let videoDownloadURL = try await videoRef.downloadURL()

        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not compress thumbnail."])
        }
        let thumbnailRef = storage.reference().child("posts/\(userID)/\(postID)_thumb.jpg")
        _ = try await thumbnailRef.putDataAsync(thumbnailData)
        let thumbnailDownloadURL = try await thumbnailRef.downloadURL()

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

// ✅ This supporting struct is essential for the memory-safe approach.
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
