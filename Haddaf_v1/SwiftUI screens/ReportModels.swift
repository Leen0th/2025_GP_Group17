import Foundation
import FirebaseAuth
import FirebaseFirestore

/// The type of content that can be reported.
enum ReportableItemType: String {
    case profile = "Profile"
    case post = "Post"
    case comment = "Comment"
}

/// A struct to identify the item being reported, used to launch the sheet.
struct ReportableItem: Identifiable {
    let id: String
    let parentId: String?
    let type: ReportableItemType
    let contentPreview: String
}

/// A single radio button option in the report view.
struct ReportOption: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String
}

/// Manages the state for the ReportView sheet.
@MainActor
final class ReportViewModel: ObservableObject {
    @Published var options: [ReportOption] = []
    @Published var selectedOption: ReportOption? // This will start as nil
    @Published var isSubmitting = false
    @Published var showSuccessAlert = false
    
    private let item: ReportableItem
    private let db = Firestore.firestore()

    init(item: ReportableItem) {
        self.item = item
        fetchOptions(for: item.type)
    }

    /// Provides the correct list of options based on the item type.
    func fetchOptions(for type: ReportableItemType) {
        switch type {
        case .profile:
            self.options = [
                .init(title: "Impersonation", description: "This profile is pretending to be someone else (e.g., a celebrity, friend, or other person)."),
                .init(title: "Other", description: "Inappropriate content, or spam.")
            ]
        case .post:
            self.options = [
                .init(title: "Video isn't about football", description: "This post contains video unrelated to football."),
                .init(title: "Video doesn't belong to user", description: "This user may have stolen this video."),
                .init(title: "Abusive Content", description: "Hate speech, violence, or spam.")
            ]
        case .comment:
            self.options = [
                .init(title: "Hate Speech or Bullying", description: "This comment attacks a person or group."),
                .init(title: "Spam or Scam", description: "This comment is irrelevant, a scam, or promotes a service."),
                .init(title: "Other", description: "Violence, or other policy violations.")
            ]
        }
    }

    // Submits the report
    func submitReport(completion: @escaping () -> Void) {
        guard let selectedOption = selectedOption else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        isSubmitting = true
        
        // 1. Create the Reporter Reference
        let reporterRef = db.collection("users").document(uid)
        
        // 2. Create the Reported Item Reference
        var itemRef: DocumentReference?
        
        switch item.type {
        case .profile:
            itemRef = db.collection("users").document(item.id)
            
        case .post:
            itemRef = db.collection("videoPosts").document(item.id)
            
        case .comment:
            // For comments, we need the parent path
            if let parentId = item.parentId {
                itemRef = db.collection("videoPosts").document(parentId).collection("comments").document(item.id)
            } else {
                print("Error: Cannot create reference for comment without parentId")
            }
        }
        
        // 3. Prepare Data
        let reportData: [String: Any] = [
            "reportedItem": itemRef as Any,
            "itemType": item.type.rawValue,
            "contentPreview": item.contentPreview,
            "reasonTitle": selectedOption.title,
            "reasonDescription": selectedOption.description,
            "reporterId": reporterRef,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "pending"
        ]
        
        // 4. Write to Firestore
        db.collection("reports").addDocument(data: reportData) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error submitting report: \(error.localizedDescription)")
                self.isSubmitting = false
            } else {
                print("Report successfully submitted.")
                self.isSubmitting = false
                self.showSuccessAlert = true
            }
        }
    }
}
