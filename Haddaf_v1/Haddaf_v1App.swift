//
//  Haddaf_v1App.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 06/10/2025.
//

import SwiftUI
import Firebase

@main
struct Haddaf_v1App: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // ✨ نقل الكود هنا بعد ما Firebase يبدأ
                    ClientNotificationScheduler.shared.startPeriodicChecks()
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}
