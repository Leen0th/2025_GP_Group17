
import Foundation

public extension Notification.Name {
    /// Fired when a new post is successfully created.
    /// The created Post object is passed inside userInfo["post"].
    static let postCreated = Notification.Name("postCreated")
    
    /// Fired when a post is successfully deleted.
    /// The deleted post's ID is passed inside userInfo["postId"].
    static let postDeleted = Notification.Name("postDeleted")
    
    /// Fired when a post's data (e.g., likes, comments) has been updated.
    /// The post's ID is passed inside userInfo["postId"].
    static let postDataUpdated = Notification.Name("postDataUpdated") 
    
    /// Fired to cancel the entire video upload flow.
    static let cancelUploadFlow = Notification.Name("cancelUploadFlow")
}
