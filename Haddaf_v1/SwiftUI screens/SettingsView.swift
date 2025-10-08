import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let primary = Color(hex: "#36796C")
    private let dividerColor = Color.black.opacity(0.15)

    @State private var selectedTab: Tab = .profile
    @State private var showVideoUpload = false

    @State private var showLogoutPopup = false
    @State private var goToWelcome = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // ✅ العنوان بالنص تمامًا
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

                // ✅ القائمة
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

                Spacer(minLength: 0)
                    .padding(.bottom, 100)
            }

            // ✅ Footer
            CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)

            // ✅ Alert مخصص ومتمركز في النص
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

                            Text("If you clicked yes you will never be able to access this account.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

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
                                    withAnimation {
                                        showLogoutPopup = false
                                        goToWelcome = true
                                    }
                                }
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(width: 100, height: 44)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(10)
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
        .sheet(isPresented: $showVideoUpload) { VideoUploadView() }
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationDestination(isPresented: $goToWelcome) {
            WelcomeView()
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - تصميم صف الإعدادات
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


