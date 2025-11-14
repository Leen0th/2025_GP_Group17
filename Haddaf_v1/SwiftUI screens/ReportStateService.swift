import Foundation
import Combine

/// A shared service to manage the state of reported content across the entire app.
/// This ensures that if you report a post in one view, it appears as "reported" in all other views.
@MainActor
final class ReportStateService: ObservableObject {
    
    /// The shared singleton instance of the service.
    static let shared = ReportStateService()
    
    // --- STATE 1: Which items are REPORTED (for filled icons) ---
    /// A set of all Post IDs that the user has reported.
    @Published private(set) var reportedPostIDs: Set<String> = []
    
    /// A set of all Comment IDs that the user has reported.
    @Published private(set) var reportedCommentIDs: Set<String> = []
    
    /// A set of all Profile IDs (using email or UID) that the user has reported.
    @Published private(set) var reportedProfileIDs: Set<String> = []

    // --- STATE 2: Which items are currently HIDDEN (for placeholder) ---
    @Published private(set) var hiddenPostIDs: Set<String> = []
    @Published private(set) var hiddenCommentIDs: Set<String> = []
    
    // Private init to ensure it's only used as a singleton.
    private init() {}
    
    // MARK: - Public Methods

    /// Marks a post as reported, causing it to be hidden.
    func reportPost(id: String) {
        reportedPostIDs.insert(id)
        hiddenPostIDs.insert(id)
    }
    
    /// Marks a comment as reported, causing it to be hidden.
    func reportComment(id: String) {
        reportedCommentIDs.insert(id)
        hiddenCommentIDs.insert(id)
    }
    
    /// Marks a profile as reported.
    func reportProfile(id: String) {
        reportedProfileIDs.insert(id)
    }
    
    /// Unhides a post that was previously reported.
    func unhidePost(id: String) {
        hiddenPostIDs.remove(id)
    }
    
    /// Unhides a comment that was previously reported.
    func unhideComment(id: String) {
        hiddenCommentIDs.remove(id)
    }
    
    /// Unhides a profile that was previously reported.
    func unhideProfile(id: String) {
        reportedProfileIDs.remove(id)
    }
}
