//
//  EmptyStateView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 24/10/2025.
//

import SwiftUI

// A reusable view for showing empty states
struct EmptyStateView: View {
    let imageName: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: imageName)
                .font(.system(size: 50))
                // MODIFIED: Use new color
                .foregroundColor(BrandColors.darkTeal.opacity(0.6))
            
            Text(message)
                // MODIFIED: Use new font
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    EmptyStateView(
        imageName: "bell.badge",
        message: "To be developed in upcoming sprints"
    )
}
