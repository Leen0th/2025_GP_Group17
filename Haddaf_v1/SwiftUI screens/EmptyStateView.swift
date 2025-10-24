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
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(message)
                .font(.custom("Poppins", size: 16))
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
        message: "You have no notifications yet. We'll let you know when something important happens!"
    )
}
