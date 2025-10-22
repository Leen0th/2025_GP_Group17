import SwiftUI

struct ContentView: View {
    @State private var showWelcomeScreen = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                if showWelcomeScreen {
                    WelcomeView()
                        .transition(.opacity)
                } else {
                    SplashVideo {
                        // Skip on tap
                        withAnimation(.easeInOut) {
                            showWelcomeScreen = true
                        }
                    }
                    .onAppear {
                        // Auto-advance after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            guard !showWelcomeScreen else { return }
                            withAnimation(.easeInOut) {
                                showWelcomeScreen = true
                            }
                        }
                    }
                }
            }
        }
    }
}
