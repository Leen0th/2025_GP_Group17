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
    
    private var videoURL: URL?
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    func processVideo(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            // 1. Get local URL for the video
            processingStateMessage = "Accessing video file..."
            guard let url = await getURL(from: item) else {
                throw NSError(domain: "VideoProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve video URL."])
            }
            self.videoURL = url

            // 2. Generate Thumbnail
            processingStateMessage = "Generating thumbnail..."
            let generatedThumbnail = try await generateThumbnail(for: url)
            self.thumbnail = generatedThumbnail
            
            // 3. Simulate performance analysis
            processingStateMessage = "Analyzing performance..."
            try await Task.sleep(nanoseconds: 2_000_000_000) // Simulate network/analysis delay
            self.performanceStats = generateMockStats()
            
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
        
        // 1. Upload Video and Thumbnail to Storage
        let (videoDownloadURL, thumbnailDownloadURL) = try await uploadFiles(videoURL: localVideoURL, thumbnail: thumbnailImage, userID: uid, postID: postID)

        // 2. Prepare Firestore data
        let userDocRef = db.collection("users").document(uid)
        let userDoc = try await userDocRef.getDocument()
        
        let userData = userDoc.data()
        let firstName = userData?["firstName"] as? String ?? ""
        let lastName = userData?["lastName"] as? String ?? ""
        let authorUsername = "\(firstName) \(lastName)"
        let authorProfilePic = userData?["profilePic"] as? String ?? ""

        let postData: [String: Any] = [
            "authorId": userDocRef,
            "authorUsername": authorUsername.trimmingCharacters(in: .whitespaces),
            "profilePic": authorProfilePic,
            "caption": caption,
            "url": videoDownloadURL.absoluteString,
            "thumbnailURL": thumbnailDownloadURL.absoluteString,
            "uploadDateTime": Timestamp(date: Date()),
            "visibility": !isPrivate, // Public is true in Firestore
            "likeCount": 0,
            "commentCount": 0
        ]
        
        // 3. Create Post Document in Firestore
        let postRef = db.collection("videoPosts").document(postID)
        try await postRef.setData(postData)
        
        // 4. Add Performance Feedback Subcollection
        let feedbackRef = postRef.collection("performanceFeedback").document("feedback")
        let performanceData: [String: Any] = [
            "passingAccuracy": performanceStats.first(where: { $0.label == "PASSING ACCURACY" })?.value ?? 0,
            "speed": performanceStats.first(where: { $0.label == "SPEED" })?.value ?? 0,
            "score": performanceStats.first(where: { $0.label == "SCORE" })?.value ?? 0
        ]
        try await feedbackRef.setData(performanceData)
    }

    // MARK: - Private Helper Methods
    
    // ✅ FIXED: Added a fallback to handle cases where a direct URL is not available.
    private func getURL(from item: PhotosPickerItem) async -> URL? {
        // First, try the simple URL loading method
        if let url = try? await item.loadTransferable(type: URL.self) {
            return url
        }

        // If that fails, fall back to loading as Data and writing to a temporary file
        if let data = try? await item.loadTransferable(type: Data.self) {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "\(UUID().uuidString).mov"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            do {
                try data.write(to: fileURL)
                return fileURL
            } catch {
                print("Failed to write video data to temporary file: \(error)")
                return nil
            }
        }
        
        return nil // Return nil if both methods fail
    }

    private func generateThumbnail(for url: URL) async throws -> UIImage {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 60)
        let cgImage = try await imageGenerator.image(at: time).image
        return UIImage(cgImage: cgImage)
    }
    
    private func uploadFiles(videoURL: URL, thumbnail: UIImage, userID: String, postID: String) async throws -> (videoURL: URL, thumbnailURL: URL) {
        // Upload Video
        let videoRef = storage.reference().child("posts/\(userID)/\(postID).mov")
        _ = try await videoRef.putFileAsync(from: videoURL)
        let videoDownloadURL = try await videoRef.downloadURL()
        
        // Upload Thumbnail
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not compress thumbnail."])
        }
        let thumbnailRef = storage.reference().child("posts/\(userID)/\(postID)_thumb.jpg")
        _ = try await thumbnailRef.putDataAsync(thumbnailData)
        let thumbnailDownloadURL = try await thumbnailRef.downloadURL()
        
        return (videoDownloadURL, thumbnailDownloadURL)
    }

    private func generateMockStats() -> [PFPostStat] {
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

