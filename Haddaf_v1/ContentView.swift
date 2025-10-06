//
//  ContentView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 06/10/2025.
//

import SwiftUI

struct ContentView: View {
    @State private var showPlayerProfile = false

    var body: some View {
        ZStack {
            // single background applies to everything inside the ZStack.
            Color.white.ignoresSafeArea()

            if showPlayerProfile {
                PlayerProfile()
                    .transition(.opacity) // Fades the MainView in.
            } else {
                // show the splash screen on top of the white background.
                SplashVideoView()
                    .onAppear {
                        // When the splash screen appears, start the timer.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                            withAnimation(.easeInOut) {
                                showPlayerProfile = true // triggers the switch to MainView.
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
