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
    
    // New: State to show the error popup and keep the last processing error
    @Published var showingAnalysisFailure = false
    @Published var lastProcessingError: Error?
    
    // New: Variables to store the required data for retrying analysis
    private var lastVideoURL: URL?
    private var lastPinpoint: CGPoint?
    private var lastFrameWidth: CGFloat?
    private var lastFrameHeight: CGFloat?
    
    // New: Task to drive the progress animation, can be cancelled on failure
    private var progressTask: Task<Void, Error>?
    // Firebase
    let db = Firestore.firestore()
    let storage = Storage.storage()
    
    //  Railway API URL
    private let apiURL = "https://footballanalysis-production.up.railway.app/analyze"
    // MARK: - Processing pipeline
    func processVideo(url: URL, pinpoint: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat) async {
        isProcessing = true
       
        // Save parameters for retry
        self.lastVideoURL = url
        self.lastPinpoint = pinpoint
        self.lastFrameWidth = frameWidth
        self.lastFrameHeight = frameHeight
        
        // Reset error state
        showingAnalysisFailure = false
        lastProcessingError = nil
        
        // Reset progress only if it's a fresh start
        if self.progress == 0.0 || self.progress >= 0.99 {
            self.progress = 0.0
        }
        print("🎯 Player pinpointed at (x,y): (\(pinpoint.x), \(pinpoint.y)), frame: \(frameWidth)x\(frameHeight)")
        let start = Date()
        // Flag to stop the progress animation when server responds or an error occurs

        var shouldContinueProgress = true
        
        do {
            processingStateMessage = "Accessing video file..."
            self.videoURL = url
            // Generate thumbnail
            processingStateMessage = "Generating thumbnail..."
            self.thumbnail = try await generateThumbnail(for: url)
            // Send video to Railway API with Retry
            processingStateMessage = "Analyzing your performance..."
            
            // Start the progress animation task
            if self.progress < 0.99 {
                progressTask = Task {
                    while shouldContinueProgress && self.progress < 0.99 && !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if shouldContinueProgress {
                            self.progress = min(self.progress + 0.004125, 0.99) //
                        }
                    }
                }
            }
            
            // Call sendToAPIWithRetry to upload the video to the FastAPI on Railway and wait for action counts.
            let actionCounts = try await sendToAPIWithRetry(videoURL: url, pinpoint: pinpoint, frameWidth: frameWidth, frameHeight: frameHeight)
            
            shouldContinueProgress = false
            progressTask?.cancel()
            self.progress = 1.0
            
            //Convert the API action counts into PFPostStat objects for the UI and Firestore.
            processingStateMessage = "Processing results..."
            self.performanceStats = [
                PFPostStat(label: "DRIBBLE", value: actionCounts["dribble"] ?? 0, maxValue: 20),
                PFPostStat(label: "PASS", value: actionCounts["pass"] ?? 0, maxValue: 50),
                PFPostStat(label: "SHOOT", value: actionCounts["shoot"] ?? 0, maxValue: 15)
            ]
            // Keep spinner visible for smooth UX
            let elapsed = Date().timeIntervalSince(start)
            if elapsed < 3 {
                let waitTime = 3 - elapsed
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            
            processingComplete = true
            
        } catch {
            // On error: stop progress and show failure popup
            shouldContinueProgress = false
            progressTask?.cancel()
            
            self.lastProcessingError = error
            self.processingStateMessage = "Analysis failed. Tap Retry."
            self.showingAnalysisFailure = true
            
            print("❌ processVideo error: \(error)")
        }
        
        
        if !showingAnalysisFailure {
            isProcessing = false
        }
    }
    
    // New: Retry analysis using the last stored parameters
    func retryAnalysis() async {
        guard let url = lastVideoURL,
              let pinpoint = lastPinpoint,
              let frameWidth = lastFrameWidth,
              let frameHeight = lastFrameHeight else {
            self.processingStateMessage = "Error: Missing video data for retry."
            return
        }
        
        // Clear failure state before retrying
        showingAnalysisFailure = false
        lastProcessingError = nil
        
        // Run the main processing pipeline again
        await processVideo(url: url, pinpoint: pinpoint, frameWidth: frameWidth, frameHeight: frameHeight)
    }
    // MARK: - Retry Wrapper
    private func sendToAPIWithRetry(videoURL: URL, pinpoint: CGPoint, frameWidth: CGFloat, frameHeight: CGFloat, maxRetries: Int = 3) async throws -> [String: Int] {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                print("📤 Upload attempt \(attempt + 1)/\(maxRetries)...")
                return try await sendToAPI(videoURL: videoURL, pinpoint: pinpoint, frameWidth: frameWidth, frameHeight: frameHeight)
            } catch let error as NSError where error.code == -1005 || error.code == -1001 || error.code == -1009 {
                
                lastError = error
                let delay = pow(2.0, Double(attempt))
                print("⚠️ Retry #\(attempt + 1)/\(maxRetries) after \(delay)s due to: \(error.localizedDescription)")
                
                // Update UI with retry message
                processingStateMessage = "Connection issue, retrying in \(Int(delay))s..."
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                processingStateMessage = "Analyzing performance..."
                continue
            } catch {
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
                
                // Progress is now handled by the animation in processVideo
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
        // 1 Enter upload mode and reset the upload progress bar.
        self.isUploading = true
        self.uploadProgress = 0.0
        // 2 Ensure there is a signed-in user before creating a post.
        guard let uid = Auth.auth().currentUser?.uid else {
            self.isUploading = false
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        // 3 Ensure that both the analyzed video URL and thumbnail image are available.
        guard let localVideoURL = videoURL, let thumb = thumbnail else {
            self.isUploading = false
            throw NSError(domain: "Upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing video or thumbnail data."])
        }
        // 4 Move the progress bar slightly to indicate that the upload has started.
        self.uploadProgress = 0.1
        // 5 Generate a unique post ID that will be used for Storage and Firestore.
        let postID = UUID().uuidString
        // 6 Upload the video and thumbnail to Firebase Storage and get their download URLs.
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
        //Convert performanceStats into a Firestore-friendly dictionary array.
        let performanceFeedbackData = self.performanceStats.map { stat -> [String: Any] in
            return [
                "label": stat.label,
                "value": stat.value,
                "maxValue": stat.maxValue
            ]
        }
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
            "likedBy": [],
            // --- Add the feedback data directly to the post document ---
            "performanceFeedback": performanceFeedbackData
        ]
        
        if let matchDate = matchDate {
            postData["matchDate"] = Timestamp(date: matchDate)
        }
        
        try await postRef.setData(postData)
        self.uploadProgress = 0.9
        // --- Add maxValue to the PostStat initializer ---
        let postStats = self.performanceStats.map { s in
            // Create the PostStat model (for the notification) using all required fields
            PostStat(label: s.label, value: Double(s.value), maxValue: Double(s.maxValue))
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
            stats: postStats, // this 'postStats' object is correctly formed
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
        
        lastVideoURL = nil
        lastPinpoint = nil
        lastFrameWidth = nil
        lastFrameHeight = nil
        showingAnalysisFailure = false
        lastProcessingError = nil
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
