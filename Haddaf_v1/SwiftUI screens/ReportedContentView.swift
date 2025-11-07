//
//  ReportedContentView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 07/11/2025.
//

import SwiftUI

/// A placeholder view that hides content the user has reported.
struct ReportedContentView: View {
    let type: ReportableItemType
    var onShow: () -> Void
    
    // Check if it's the compact comment version
    private var isComment: Bool {
        type == .comment
    }

    var body: some View {
        VStack(alignment: .center, spacing: isComment ? 8 : 16) { // Smaller spacing for comment
            Image(systemName: "flag.fill")
                .font(isComment ? .body : .title) // Smaller icon for comment
                .foregroundColor(.secondary)
            
            Text("You reported this \(type.rawValue.lowercased()).")
                .font(.system(size: isComment ? 14 : 16, weight: .medium, design: .rounded)) // Smaller text for comment
                .foregroundColor(.secondary)
            
            Button("View Content") {
                onShow()
            }
            .font(.system(size: isComment ? 13 : 14, weight: .bold, design: .rounded)) // Smaller button for comment
            .foregroundColor(BrandColors.darkTeal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isComment ? 10 : 20) 
        .padding(.horizontal)
        .background(BrandColors.lightGray.opacity(0.7))
        .cornerRadius(isComment ? 12 : 20) // Smaller corner radius for comment
    }
}
