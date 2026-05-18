import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Notification Settings View
struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession
    @StateObject private var viewModel = NotificationSettingsViewModel()

    private let primary = BrandColors.darkTeal

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Notification")
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
                .padding(.bottom, 20)

                if viewModel.isLoadingRole {
                    ProgressView()
                        .tint(primary)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        if session.role == "coach" {
                            // ─── Coach Toggles ───
                            NotificationToggleRow(
                                title: "Upcoming Match Reminders",
                                isEnabled: $viewModel.upcomingMatchEnabled,
                                showDivider: true
                            )
                            NotificationToggleRow(
                                title: "Academies",
                                isEnabled: $viewModel.academiesEnabled,
                                showDivider: false
                            )
                        } else {
                            // ─── Player Toggles ───
                            NotificationToggleRow(
                                title: "New Challenge",
                                isEnabled: $viewModel.newChallengeEnabled,
                                showDivider: true
                            )
                            NotificationToggleRow(
                                title: "Upcoming Match Reminders",
                                isEnabled: $viewModel.upcomingMatchEnabled,
                                showDivider: true
                            )
                            NotificationToggleRow(
                                title: "Challenge Ended",
                                isEnabled: $viewModel.challengeEndedEnabled,
                                showDivider: true
                            )
                            NotificationToggleRow(
                                title: "Invitations from Academy",
                                isEnabled: $viewModel.academyInvitationsEnabled,
                                showDivider: false
                            )
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.loadSettings(role: session.role ?? "player")
        }
    }
}

// MARK: - Toggle Row Component
private struct NotificationToggleRow: View {
    let title: String
    @Binding var isEnabled: Bool
    let showDivider: Bool

    private let primary = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(primary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if showDivider {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 1)
                    .padding(.leading, 24)
            }
        }
    }
}

// MARK: - ViewModel
class NotificationSettingsViewModel: ObservableObject {
    // Shared
    @Published var upcomingMatchEnabled = true { didSet { saveIfReady() } }

    // Player only
    @Published var newChallengeEnabled       = true { didSet { saveIfReady() } }
    @Published var challengeEndedEnabled     = true { didSet { saveIfReady() } }
    @Published var academyInvitationsEnabled = true { didSet { saveIfReady() } }

    // Coach only
    @Published var academiesEnabled = true { didSet { saveIfReady() } }

    @Published var isLoadingRole: Bool = true
    private(set) var userRole: String = "player"

    private let db = Firestore.firestore()
    private var isLoading = false

    // MARK: Load settings (role passed from AppSession)
    func loadSettings(role: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoadingRole = false
            return
        }

        isLoading = true
        isLoadingRole = true
        userRole = role

        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.isLoadingRole = false
                }
                return
            }

            DispatchQueue.main.async {
                // Shared
                self.upcomingMatchEnabled = data["notif_upcomingMatch"] as? Bool ?? true

                // Player
                self.newChallengeEnabled       = data["notif_newChallenge"]       as? Bool ?? true
                self.challengeEndedEnabled     = data["notif_challengeEnded"]     as? Bool ?? true
                self.academyInvitationsEnabled = data["notif_academyInvitations"] as? Bool ?? true

                // Coach
                self.academiesEnabled = data["notif_academies"] as? Bool ?? true

                self.isLoading = false
                self.isLoadingRole = false
                print("✅ Role from session: \(self.userRole) | Settings loaded")
            }
        }
    }

    // MARK: Save
    private func saveIfReady() {
        guard !isLoading else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }

        var settings: [String: Any] = [
            "notif_upcomingMatch": upcomingMatchEnabled
        ]

        if userRole == "coach" {
            settings["notif_academies"] = academiesEnabled
        } else {
            settings["notif_newChallenge"]       = newChallengeEnabled
            settings["notif_challengeEnded"]     = challengeEndedEnabled
            settings["notif_academyInvitations"] = academyInvitationsEnabled
        }

        db.collection("users").document(userId).updateData(settings) { error in
            if let error = error {
                print("❌ Save error: \(error)")
            } else {
                print("✅ Settings saved for role: \(self.userRole)")
            }
        }
    }
}
