import SwiftUI
import FirebaseAuth
import FirebaseMessaging

struct SettingsView: View {
    @EnvironmentObject var session: AppSession
    // The environment object for dismissing the view
    @Environment(\.dismiss) private var dismiss
    // The user's profile data to be used by `EditProfileView`
    @ObservedObject var userProfile: UserProfile

    private let primary = BrandColors.darkTeal
    private let dividerColor = Color.black.opacity(0.15)
    
    // Controls the visibility of the logout confirmation popup
    @State private var showLogoutPopup = false
    // Triggers the `navigationDestination` to the `WelcomeView` after a successful logout
    @State private var goToWelcome = false

    // Show a loading indicator while the logout process is active
    @State private var isSigningOut = false
    // String to display any error that occurs during the sign-out process
    @State private var signOutError: String?

    var body: some View {
       ZStack {
           BrandColors.backgroundGradientEnd.ignoresSafeArea()

           VStack(spacing: 0) {
               ZStack {
                   Text("Settings")
                       .font(.system(size: 28, weight: .medium, design: .rounded))
                       .foregroundColor(primary)
                       .frame(maxWidth: .infinity, alignment: .center)

                   HStack {
                       Button { dismiss() } label: {
                           Image(systemName: "chevron.left")
                               .font(.system(size: 18, weight: .semibold))
                               .foregroundColor(primary)
                               .padding(10)
                               .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                       }
                       Spacer()
                   }
               }
               .padding(.horizontal, 16)
               .padding(.top, 8)
               .padding(.bottom, 14)

               // MARK: - Settings List
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
               .background(BrandColors.background)
               .clipShape(RoundedRectangle(cornerRadius: 16))
               .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
               .padding(.horizontal, 16)

               Spacer()
           }

           // MARK: - Logout Popup
           if showLogoutPopup {
               Color.black.opacity(0.4)
                   .ignoresSafeArea()
                   .transition(.opacity)

               GeometryReader { geometry in
                   VStack {
                       Spacer()
                       VStack(spacing: 20) {
                           Text("Logout?")
                               .font(.system(size: 20, weight: .semibold, design: .rounded))
                               .foregroundColor(.primary)
                               .multilineTextAlignment(.center)

                           Text("Are you sure you want to log out from this device?")
                               .font(.system(size: 14, design: .rounded))
                               .foregroundColor(.secondary)
                               .multilineTextAlignment(.center)
                               .padding(.horizontal, 24)

                           // Loading spinner
                           if isSigningOut {
                               ProgressView().tint(primary).padding(.top, 4)
                           }

                           // Error message
                           if let signOutError {
                               Text(signOutError)
                                   .font(.system(size: 13, design: .rounded))
                                   .foregroundColor(.red)
                                   .multilineTextAlignment(.center)
                                   .padding(.horizontal, 16)
                           }

                           // Action Buttons
                           HStack(spacing: 16) {
                               Button("No") {
                                   withAnimation { showLogoutPopup = false }
                               }
                               .font(.system(size: 17, weight: .semibold, design: .rounded))
                               .foregroundColor(BrandColors.darkGray)
                               .frame(maxWidth: .infinity)
                               .padding(.vertical, 12)
                               .background(BrandColors.lightGray)
                               .cornerRadius(12)

                               Button("Yes") {
                                   performLogout()
                               }
                               .font(.system(size: 17, weight: .semibold, design: .rounded))
                               .foregroundColor(.white)
                               .frame(maxWidth: .infinity)
                               .padding(.vertical, 12)
                               .background(Color.red)
                               .cornerRadius(12)
                               .disabled(isSigningOut)
                           }
                           .padding(.top, 4)
                       }
                       .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
                       .frame(width: 320)
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
        // Navigation destination to go back to Welcome screen after logout
       .navigationDestination(isPresented: $goToWelcome) {
           WelcomeView()
       }
       .navigationBarBackButtonHidden(true)
   }

    // MARK: - Logout Logic
    private func performLogout() {
        isSigningOut = true
        signOutError = nil

        clearLocalCaches()

        // Delete the FCM token so this device no longer receives push notifications for the user who is logging out.
        Messaging.messaging().deleteToken { _ in
            // proceed with signing the user out.
            self.signOutFirebase()
        }
    }

    private func signOutFirebase() {
        do {
            try Auth.auth().signOut()
            // Success: trigger navigation
            withAnimation {
                isSigningOut = false
                showLogoutPopup = false
                goToWelcome = true // This triggers the .navigationDestination
            }
        } catch {
            // Failure: show error
            isSigningOut = false
            signOutError = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    // Removes sensitive or user-specific data from `UserDefaults` during logout
    // Clears any saved profile drafts or cached user profile information
    private func clearLocalCaches() {
        UserDefaults.standard.removeObject(forKey: "signup_profile_draft")
        UserDefaults.standard.removeObject(forKey: "current_user_profile")
        UserDefaults.standard.synchronize()
        // Clear the shared report state so the next user doesn't see old reports
        ReportStateService.shared.reset()
    }

    // MARK: - View Builders
    private func settingsRow(icon: String, title: String,
                                 iconColor: Color, showChevron: Bool, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }
}
