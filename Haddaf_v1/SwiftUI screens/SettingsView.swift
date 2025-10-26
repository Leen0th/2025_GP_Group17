import SwiftUI
import FirebaseAuth
import FirebaseMessaging

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // --- ADDED: To pass to EditProfileView ---
    @ObservedObject var userProfile: UserProfile

    // MODIFIED: Use new BrandColors
    private let primary = BrandColors.darkTeal
    private let dividerColor = Color.black.opacity(0.15)

    @State private var showLogoutPopup = false
    @State private var goToWelcome = false

    // UI states for logout
    @State private var isSigningOut = false
    @State private var signOutError: String?

    var body: some View {
       ZStack {
           // MODIFIED: Use new gradient background
           BrandColors.backgroundGradientEnd.ignoresSafeArea()

           VStack(spacing: 0) {
               // Header
               ZStack {
                   Text("Settings")
                       // MODIFIED: Use new font
                       .font(.system(size: 28, weight: .medium, design: .rounded))
                       .foregroundColor(primary)
                       .frame(maxWidth: .infinity, alignment: .center)

                   HStack {
                       Button { dismiss() } label: {
                           Image(systemName: "chevron.left")
                               .font(.system(size: 18, weight: .semibold))
                               .foregroundColor(primary)
                               .padding(10)
                               // MODIFIED: Use new background
                               .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                       }
                       Spacer()
                   }
               }
               .padding(.horizontal, 16)
               .padding(.top, 8)
               .padding(.bottom, 14)

               // List
               VStack(spacing: 0) {
                   NavigationLink {
                       EditProfileView(userProfile: userProfile)
                   } label: {
                       settingsRow(icon: "person", title: "Edit Profile",
                                   iconColor: primary, showChevron: true, showDivider: true)
                   }
                   
                   NavigationLink {
                       NotificationsView()
                   } label: {
                       settingsRow(icon: "bell", title: "Notifications",
                                   iconColor: primary, showChevron: true, showDivider: true)
                   }

                   NavigationLink {
                       ChangePasswordView()
                   } label: {
                       settingsRow(icon: "lock", title: "Change Password",
                                   iconColor: primary, showChevron: true, showDivider: true)
                   }

                   Button {
                       showLogoutPopup = true
                   } label: {
                       settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Logout",
                                   iconColor: primary, showChevron: false, showDivider: false)
                   }
               }
               // MODIFIED: Use new card style
               .background(BrandColors.background)
               .clipShape(RoundedRectangle(cornerRadius: 16))
               .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
               .padding(.horizontal, 16)

               Spacer()
           }

           // Logout Popup (centered)
           if showLogoutPopup {
               Color.black.opacity(0.4)
                   .ignoresSafeArea()
                   .transition(.opacity)

               GeometryReader { geometry in
                   VStack {
                       Spacer()
                       VStack(spacing: 20) {
                           Text("Logout?")
                               // MODIFIED: Use new font
                               .font(.system(size: 20, weight: .semibold, design: .rounded))
                               .foregroundColor(.primary)
                               .multilineTextAlignment(.center)

                           Text("Are you sure you want to log out from this device?")
                               // MODIFIED: Use new font
                               .font(.system(size: 14, design: .rounded))
                               .foregroundColor(.secondary)
                               .multilineTextAlignment(.center)
                               .padding(.horizontal, 24)

                           if isSigningOut {
                               ProgressView().tint(primary).padding(.top, 4) // MODIFIED
                           }

                           if let signOutError {
                               Text(signOutError)
                                   // MODIFIED: Use new font
                                   .font(.system(size: 13, design: .rounded))
                                   .foregroundColor(.red)
                                   .multilineTextAlignment(.center)
                                   .padding(.horizontal, 16)
                           }

                           HStack(spacing: 16) { // MODIFIED
                               Button("No") {
                                   withAnimation { showLogoutPopup = false }
                               }
                               // MODIFIED: Use new font and style
                               .font(.system(size: 17, weight: .semibold, design: .rounded))
                               .foregroundColor(BrandColors.darkGray)
                               .frame(maxWidth: .infinity) // MODIFIED
                               .padding(.vertical, 12) // MODIFIED
                               .background(BrandColors.lightGray) // MODIFIED
                               .cornerRadius(12) // MODIFIED

                               Button("Yes") {
                                   performLogout()
                               }
                               // MODIFIED: Use new font and style
                               .font(.system(size: 17, weight: .semibold, design: .rounded))
                               .foregroundColor(.red)
                               .frame(maxWidth: .infinity) // MODIFIED
                               .padding(.vertical, 12) // MODIFIED
                               .background(Color.red.opacity(0.1)) // MODIFIED
                               .cornerRadius(12) // MODIFIED
                               .disabled(isSigningOut)
                           }
                           .padding(.top, 4)
                       }
                       .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24)) // MODIFIED
                       .frame(width: 320)
                       // MODIFIED: Use new background
                       .background(BrandColors.background)
                       .cornerRadius(20)
                       .shadow(radius: 12)
                       Spacer()
                   }
                   .frame(width: geometry.size.width, height: geometry.size.height)
               }
               .transition(.scale)
           }
       }
       .animation(.easeInOut, value: showLogoutPopup)
       .navigationDestination(isPresented: $goToWelcome) {
           WelcomeView()
       }
       .navigationBarBackButtonHidden(true)
   }

    // MARK: - Logout logic (يشمل حذف FCM token)
    private func performLogout() {
        isSigningOut = true
        signOutError = nil

        clearLocalCaches()

        Messaging.messaging().deleteToken { _ in
            self.signOutFirebase()
        }
    }

    private func signOutFirebase() {
        do {
            try Auth.auth().signOut()
            withAnimation {
                isSigningOut = false
                showLogoutPopup = false
                goToWelcome = true
            }
        } catch {
            isSigningOut = false
            signOutError = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    private func clearLocalCaches() {
        UserDefaults.standard.removeObject(forKey: "signup_profile_draft")
        UserDefaults.standard.removeObject(forKey: "current_user_profile")
        UserDefaults.standard.synchronize()
    }

    private func settingsRow(icon: String, title: String,
                                 iconColor: Color, showChevron: Bool, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) { // MODIFIED: Increased spacing
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)

                Text(title)
                    // MODIFIED: Use new font
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(BrandColors.darkGray) // MODIFIED

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7)) // MODIFIED
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 60) // MODIFIED: Increased padding
            }
        }
    }
}
