//
//  PlaceholderViews.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 09/10/2025.
//

import SwiftUI

// MARK: - Placeholder Tab Screens
struct DiscoveryView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Discovery Page")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
    }
}

struct TeamsView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Teams Page")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
    }
}

struct ChallengeView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Challenge Page")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Placeholder Sheet Screens
struct VideoUploadView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Video Upload Page")
                .font(.largeTitle)
        }
    }
}
