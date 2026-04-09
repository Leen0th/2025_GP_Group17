import SwiftUI
import Firebase
import GooglePlaces // ✨ أضيفي هذا

@main
struct Haddaf_v1App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    ClientNotificationScheduler.shared.startPeriodicChecks()
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        FirebaseApp.configure()

        // 🔥 هنا تحطين المفتاح
        GMSPlacesClient.provideAPIKey("AIzaSyB3s4XEm1y_Hn6Nf6WmwR6VXXXxf-qZyvQ")

        return true
    }
}
