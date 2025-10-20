import SwiftUI
import FirebaseAuth
import FirebaseMessaging

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let primary = colorHex("#36796C")
    private let dividerColor = Color.black.opacity(0.15)

    @State private var showLogoutPopup = false
    @State private var goToWelcome = false

    // UI states for logout
    @State private var isSigningOut = false
    @State private var signOutError: String?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Settings")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(primary)
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.05)))
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
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)

                            Text("Are you sure you want to log out from this device?")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            if isSigningOut {
                                ProgressView().padding(.top, 4)
                            }

                            if let signOutError {
                                Text(signOutError)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }

                            HStack(spacing: 24) {
                                Button("No") {
                                    withAnimation { showLogoutPopup = false }
                                }
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 100, height: 44)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(10)

                                Button("Yes") {
                                    performLogout()
                                }
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(width: 100, height: 44)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(10)
                                .disabled(isSigningOut)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .frame(width: 320)
                        .background(Color.white)
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.custom("Poppins", size: 17))
                    .foregroundColor(.primary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 56)
            }
        }
    }
}

// Local hex color helper
private func colorHex(_ hex: String) -> Color {
    let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: s).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch s.count {
    case 3: (a, r, g, b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
    case 6: (a, r, g, b) = (255, int>>16, int>>8 & 0xFF, int & 0xFF)
    case 8: (a, r, g, b) = (int>>24, int>>16 & 0xFF, int>>8 & 0xFF, int & 0xFF)
    default: (a, r, g, b) = (255,0,0,0)
    }
    return Color(.sRGB,
                 red: Double(r)/255, green: Double(g)/255,
                 blue: Double(b)/255, opacity: Double(a)/255)
}




