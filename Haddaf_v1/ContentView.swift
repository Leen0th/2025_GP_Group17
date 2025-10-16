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
                    SplashVideo()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
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
