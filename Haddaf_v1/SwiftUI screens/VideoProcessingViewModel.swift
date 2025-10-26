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
    
    @Published var progress: Double = 0.0
    @Published var isUploading: Bool = false
    @Published var uploadProgress: Double = 0.0
    
    @Published var thumbnail: UIImage?
    @Published var videoURL: URL?
    @Published var performanceStats: [PFPostStat] = []

    // Firebase
    let db = Firestore.firestore()
    let storage = Storage.storage()
    
    // 🔥 Railway API URL
    private let apiURL = "https://footballanalysis-production.up.railway.app/analyze"

    // MARK: - Processing pipeline
    func processVideo(url: URL, pinpoint: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat) async {
        isProcessing = true
        defer { isProcessing = false }
        
        self.progress = 0.0
        
        print("🎯 Player pinpointed at (x,y): (\(pinpoint.x), \(pinpoint.y)), frame: \(frameWidth)x\(frameHeight)")

        let start = Date()

        do {
            processingStateMessage = "Accessing video file..."
            self.videoURL = url
            self.progress = 0.1 // 10%

            // Generate thumbnail
            processingStateMessage = "Generating thumbnail..."
            self.thumbnail = try await generateThumbnail(for: url)
            self.progress = 0.2 // 20%

            // 🚀 Send video to Railway API with Retry
            processingStateMessage = "Uploading to AI server..."
            let actionCounts = try await sendToAPIWithRetry(videoURL: url, pinpoint: pinpoint, frameWidth: frameWidth, frameHeight: frameHeight)
            self.progress = 0.8 // 80%

            // Convert to performanceStats
            processingStateMessage = "Processing results..."
            self.performanceStats = [
                PFPostStat(label: "DRIBBLE", value: actionCounts["dribble"] ?? 0, maxValue: 20),
                PFPostStat(label: "PASS", value: actionCounts["pass"] ?? 0, maxValue: 50),
                PFPostStat(label: "SHOOT", value: actionCounts["shoot"] ?? 0, maxValue: 15)
            ]
            self.progress = 0.9 // 90%

            // Keep spinner visible for smooth UX
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 3 {
                let waitTime = 3 - elapsed
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            
            self.progress = 1.0 // 100%
            processingComplete = true
            
        } catch {
            processingStateMessage = "Error: \(error.localizedDescription)"
            print("❌ processVideo error: \(error)")
        }
    }
    
    // MARK: - Retry Wrapper
    private func sendToAPIWithRetry(videoURL: URL, pinpoint: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat, maxRetries: Int = 3) async throws -> [String: Int] {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                print("📤 Upload attempt \(attempt + 1)/\(maxRetries)...")
                return try await sendToAPI(videoURL: videoURL, pinpoint: pinpoint, frameWidth: frameWidth, frameHeight: frameHeight)
            } catch let error as NSError where error.code == -1005 || error.code == -1001 || error.code == -1009 {
                // Network errors: -1005 (connection lost), -1001 (timeout), -1009 (no internet)
                lastError = error
                let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s
                print("⚠️ Retry #\(attempt + 1)/\(maxRetries) after \(delay)s due to: \(error.localizedDescription)")
                
                // Update UI with retry message
                processingStateMessage = "Connection issue, retrying in \(Int(delay))s..."
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                processingStateMessage = "Uploading to AI server..."
                continue
            } catch {
                // Other errors - don't retry
                throw error
            }
        }
        
        throw lastError ?? NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed after \(maxRetries) retries"])
    }
    
    // MARK: - Send to Railway API (Optimized with Streaming)
    private func sendToAPI(videoURL: URL, pinpoint: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat) async throws -> [String: Int] {
        // Create Default Session with long timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 minutes for request
        config.timeoutIntervalForResource = 1800 // 30 minutes for resource
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 1
        
        let session = URLSession(configuration: config)
        
        // Create Temporary File for Multipart Body
        let tempDir = FileManager.default.temporaryDirectory
        let boundaryFile = tempDir.appendingPathComponent("upload_\(UUID().uuidString).tmp")
        
        do {
            // Build Multipart Body in a temporary file
            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: URL(string: apiURL)!)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 1800 // 30 minutes
            
            // Create FileHandle for writing
            FileManager.default.createFile(atPath: boundaryFile.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: boundaryFile)
            
            // Send Normalized Coordinates
            let normalizedX = pinpoint.x / frameWidth
            let normalizedY = pinpoint.y / frameHeight
            var bodyPart = "--\(boundary)\r\n".data(using: .utf8)!
            bodyPart.append("Content-Disposition: form-data; name=\"x\"\r\n\r\n".data(using: .utf8)!)
            bodyPart.append("\(normalizedX)\r\n".data(using: .utf8)!)
            fileHandle.write(bodyPart)
            
            bodyPart = "--\(boundary)\r\n".data(using: .utf8)!
            bodyPart.append("Content-Disposition: form-data; name=\"y\"\r\n\r\n".data(using: .utf8)!)
            bodyPart.append("\(normalizedY)\r\n".data(using: .utf8)!)
            fileHandle.write(bodyPart)
            
            // Send Frame Dimensions
            bodyPart = "--\(boundary)\r\n".data(using: .utf8)!
            bodyPart.append("Content-Disposition: form-data; name=\"width\"\r\n\r\n".data(using: .utf8)!)
            bodyPart.append("\(frameWidth)\r\n".data(using: .utf8)!)
            fileHandle.write(bodyPart)
            
            bodyPart = "--\(boundary)\r\n".data(using: .utf8)!
            bodyPart.append("Content-Disposition: form-data; name=\"height\"\r\n\r\n".data(using: .utf8)!)
            bodyPart.append("\(frameHeight)\r\n".data(using: .utf8)!)
            fileHandle.write(bodyPart)
            
            // Write Video Header
            bodyPart = "--\(boundary)\r\n".data(using: .utf8)!
            bodyPart.append("Content-Disposition: form-data; name=\"video\"; filename=\"video.mp4\"\r\n".data(using: .utf8)!)
            bodyPart.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
            fileHandle.write(bodyPart)
            
            // Read video in chunks (Streaming)
            print("📹 Reading video file in chunks...")
            let videoHandle = try FileHandle(forReadingFrom: videoURL)
            let chunkSize = 1024 * 1024 // 1MB chunks
            var totalBytesRead: UInt64 = 0
            
            // Get file size for progress
            let videoAttributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let fileSize = videoAttributes[.size] as? UInt64 ?? 0
            print("📊 Video file size: \(Double(fileSize) / 1024 / 1024) MB")
            
            while true {
                let chunk = videoHandle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                fileHandle.write(chunk)
                totalBytesRead += UInt64(chunk.count)
                
                // Update progress
                if fileSize > 0 {
                    let uploadProgress = Double(totalBytesRead) / Double(fileSize) * 0.3 // 30% of total progress
                    await MainActor.run {
                        self.progress = 0.2 + uploadProgress
                    }
                }
            }
            
            try videoHandle.close()
            print("✅ Video chunks written to temp file")
            
            // Finalize Multipart
            bodyPart = "\r\n--\(boundary)--\r\n".data(using: .utf8)!
            fileHandle.write(bodyPart)
            try fileHandle.close()
            
            // Upload Task
            print("📤 Uploading multipart data to Railway API...")
            print("🌐 API URL: \(apiURL)")
            
            let (data, response) = try await session.upload(for: request, fromFile: boundaryFile)
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: boundaryFile)
            
            // Process response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            print("📥 Response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ API Error (\(httpResponse.statusCode)): \(errorMsg)")
                throw NSError(domain: "API", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
            
            // Parse JSON
            struct APIResponse: Codable {
                let success: Bool
                let action_counts: [String: Int]
                let crops_url: String?
                let total_crops: Int?
            }
            
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(APIResponse.self, from: data)
            
            guard apiResponse.success else {
                throw NSError(domain: "API", code: -2, userInfo: [NSLocalizedDescriptionKey: "API returned success=false"])
            }
            
            print("✅ Action counts received: \(apiResponse.action_counts)")
            
            if let cropsURL = apiResponse.crops_url {
                print("📸 Total crops: \(apiResponse.total_crops ?? 0)")
                print("🌐 View crops at: \(cropsURL)")
                print("")
                print("========================================")
                print("🎯 COPY THIS URL TO VIEW IMAGES:")
                print(cropsURL)
                print("========================================")
                print("")
            }
            
            return apiResponse.action_counts
            
        } catch {
            // Clean up on error
            try? FileManager.default.removeItem(at: boundaryFile)
            print("❌ Error in sendToAPI: \(error)")
            throw error
        }
    }

    // MARK: - Create post
    func createPost(title: String, isPrivate: Bool, matchDate: Date?) async throws {
        self.isUploading = true
        self.uploadProgress = 0.0
        
        guard let uid = Auth.auth().currentUser?.uid else {
            self.isUploading = false
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        guard let localVideoURL = videoURL, let thumb = thumbnail else {
            self.isUploading = false
            throw NSError(domain: "Upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing video or thumbnail data."])
        }
        
        self.uploadProgress = 0.1

        let postID = UUID().uuidString
        let (videoDL, thumbDL) = try await uploadFiles(videoURL: localVideoURL, thumbnail: thumb, userID: uid, postID: postID)
        self.uploadProgress = 0.6

        let userRef = db.collection("users").document(uid)
        let userDoc = try await userRef.getDocument()
        let data = userDoc.data() ?? [:]
        let first = (data["firstName"] as? String) ?? ""
        let last  = (data["lastName"]  as? String) ?? ""
        let authorUsername = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let profilePic = (data["profilePic"] as? String) ?? ""
        self.uploadProgress = 0.7

        let postRef = db.collection("videoPosts").document(postID)
        var postData: [String: Any] = [
            "authorId": userRef,
            "authorUsername": authorUsername,
            "profilePic": profilePic,
            "caption": title,
            "url": videoDL.absoluteString,
            "thumbnailURL": thumbDL.absoluteString,
            "uploadDateTime": Timestamp(date: Date()),
            "visibility": !isPrivate,
            "likeCount": 0,
            "commentCount": 0,
            "likedBy": []
        ]
        
        if let matchDate = matchDate {
            postData["matchDate"] = Timestamp(date: matchDate)
        }
        
        try await postRef.setData(postData)
        self.uploadProgress = 0.8

        let perfRef = postRef.collection("performanceFeedback").document("feedback")
        let perfData: [String: Any]
        if !self.performanceStats.isEmpty {
            perfData = [
                "stats": Dictionary(uniqueKeysWithValues: self.performanceStats.map {
                    ($0.label, ["value": $0.value])
                })
            ]
        } else {
            perfData = ["stats": [:]]
        }
        try await perfRef.setData(perfData)
        self.uploadProgress = 0.9

        let postStats = self.performanceStats.map { s in
            PostStat(label: s.label, value: Double(s.value))
        }

        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy HH:mm"
        
        let newPost = Post(
            id: postID,
            imageName: thumbDL.absoluteString,
            videoURL: videoDL.absoluteString,
            caption: title,
            timestamp: df.string(from: Date()),
            isPrivate: isPrivate,
            authorName: authorUsername,
            authorImageName: profilePic,
            likeCount: 0,
            commentCount: 0,
            likedBy: [],
            isLikedByUser: false,
            stats: postStats,
            matchDate: matchDate
        )
        NotificationCenter.default.post(name: .postCreated, object: nil, userInfo: ["post": newPost])
        
        self.uploadProgress = 1.0
        self.isUploading = false
    }

    func resetAfterPosting() {
        processingComplete = false
        videoURL = nil
        thumbnail = nil
        performanceStats = []
        processingStateMessage = "Preparing video..."
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

    private func uploadFiles(videoURL: URL, thumbnail: UIImage, userID: String, postID: String) async throws -> (videoURL: URL, thumbnailURL: URL) {
        let videoRef = storage.reference().child("posts/\(userID)/\(postID).mov")
        let thumbRef = storage.reference().child("posts/\(userID)/\(postID)_thumb.jpg")

        let metaVideo = StorageMetadata()
        metaVideo.contentType = "video/mp4"
        let metaThumb = StorageMetadata()
        metaThumb.contentType = "image/jpeg"

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

        let videoData = try Data(contentsOf: videoURL)
        try await retry { _ = try await videoRef.putDataAsync(videoData, metadata: metaVideo) }

        try await Task.sleep(nanoseconds: 500_000_000)
        let videoDownloadURL = try await retry { try await videoRef.downloadURL() }

        guard let thumbData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "Upload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not compress thumbnail."])
        }
        try await retry { _ = try await thumbRef.putDataAsync(thumbData, metadata: metaThumb) }

        try await Task.sleep(nanoseconds: 500_000_000)
        let thumbDownloadURL = try await retry { try await thumbRef.downloadURL() }

        return (videoDownloadURL, thumbDownloadURL)
    }
}
