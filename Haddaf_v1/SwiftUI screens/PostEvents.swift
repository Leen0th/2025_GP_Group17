//
//  PostEvents.swift
//  Haddaf_v1
//
//  Created by Lujain Alhussan on 24/04/1447 AH.
//

import Foundation

public extension Notification.Name {
    /// Fired when a new post is successfully created.
    /// The created Post object is passed inside userInfo["post"].
    static let postCreated = Notification.Name("postCreated")
}
