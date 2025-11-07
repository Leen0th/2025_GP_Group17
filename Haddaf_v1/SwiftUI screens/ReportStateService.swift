//
//  ReportStateService.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 07/11/2025.
//

import Foundation
import Combine

/// A shared service to manage the state of reported content across the entire app.
/// This ensures that if you report a post in one view, it appears as "reported" in all other views.
@MainActor
final class ReportStateService: ObservableObject {
    
    /// The shared singleton instance of the service.
    static let shared = ReportStateService()
    
    /// A set of all Post IDs that the user has reported.
    @Published private(set) var reportedPostIDs: Set<String> = []
    
    /// A set of all Comment IDs that the user has reported.
    @Published private(set) var reportedCommentIDs: Set<String> = []
    
    // Private init to ensure it's only used as a singleton.
    private init() {}
    
    // MARK: - Public Methods

    /// Marks a post as reported, causing it to be hidden.
    func reportPost(id: String) {
        reportedPostIDs.insert(id)
    }
    
    /// Marks a comment as reported, causing it to be hidden.
    func reportComment(id: String) {
        reportedCommentIDs.insert(id)
    }
    
    /// Unhides a post that was previously reported.
    func unhidePost(id: String) {
        reportedPostIDs.remove(id)
    }
    
    /// Unhides a comment that was previously reported.
    func unhideComment(id: String) {
        reportedCommentIDs.remove(id)
    }
}
