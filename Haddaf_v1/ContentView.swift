import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var session = AppSession()
    @State private var showWelcomeScreen = false
    @State private var navigationID = UUID() // ⬅️ لإعادة بناء الـ NavigationStack

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
        .id(navigationID) // ⬅️ إعادة بناء NavigationStack
        .environmentObject(session)
        .onReceive(NotificationCenter.default.publisher(for: .forceLogout)) { _ in
            // عند logout، غيّر الـ ID لإعادة بناء الـ NavigationStack بالكامل
            navigationID = UUID()
        }
    }
}
