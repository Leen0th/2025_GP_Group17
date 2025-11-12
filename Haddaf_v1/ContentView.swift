import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var session = AppSession()

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
                        withAnimation(.easeInOut) { showWelcomeScreen = true }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            guard !showWelcomeScreen else { return }
                            withAnimation(.easeInOut) { showWelcomeScreen = true }
                        }
                    }
                }
            }
        }
        .environmentObject(session) // ⬅️ نشر الجلسة لكل الشاشات
    }
}

