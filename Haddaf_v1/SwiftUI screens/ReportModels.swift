import Foundation

/// The type of content that can be reported.
enum ReportableItemType: String {
    case profile = "Profile"
    case post = "Post"
    case comment = "Comment"
}

/// A struct to identify the item being reported, used to launch the sheet.
struct ReportableItem: Identifiable {
    let id: String // The Firestore ID of the item
    let type: ReportableItemType
    let contentPreview: String // e.g., username, post caption, or comment text
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
    @Published var selectedOption: ReportOption? // This will now start as nil
    @Published var isSubmitting = false
    @Published var showSuccessAlert = false
    
    private let item: ReportableItem

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
                .init(title: "Other", description: "video title contain hate speech, or spam.")
            ]
        case .comment:
            self.options = [
                .init(title: "Hate Speech or Bullying", description: "This comment attacks a person or group."),
                .init(title: "Spam or Scam", description: "This comment is irrelevant, a scam, or promotes a service."),
                .init(title: "Other", description: "Violence, or other policy violations.")
            ]
        }
    }

    /// Simulates submitting the report to a backend.
    func submitReport(completion: @escaping () -> Void) {
        guard selectedOption != nil else { return }
        
        isSubmitting = true
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            await MainActor.run {
                isSubmitting = false
                showSuccessAlert = true
                // The alert's "OK" button will trigger the completion
            }
        }
    }
}
