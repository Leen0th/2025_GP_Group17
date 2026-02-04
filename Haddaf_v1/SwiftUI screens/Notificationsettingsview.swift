import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Notification Settings View (FIXED VERSION)
struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
                        Button {
                            dismiss()
                        } label: {
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
                
                // Settings List
                VStack(spacing: 0) {
                    // New Challenge Toggle
                    NotificationToggleRow(
                        title: "New Challenge",
                        isEnabled: $viewModel.newChallengeEnabled,
                        showDivider: true
                    )
                    
                    // Upcoming Match Reminders Toggle
                    NotificationToggleRow(
                        title: "Upcoming Match Reminders",
                        isEnabled: $viewModel.upcomingMatchEnabled,
                        showDivider: true
                    )
                    
                    // Challenge Ended Toggle
                    NotificationToggleRow(
                        title: "Challenge Ended",
                        isEnabled: $viewModel.challengeEndedEnabled,
                        showDivider: false
                    )
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                .padding(.horizontal, 16)
                
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.loadSettings()
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

// MARK: - View Model (FIXED)
class NotificationSettingsViewModel: ObservableObject {
    @Published var newChallengeEnabled = true {
        didSet {
            saveSettings()
        }
    }
    
    @Published var upcomingMatchEnabled = true {
        didSet {
            saveSettings()
        }
    }
    
    @Published var challengeEndedEnabled = true {
        didSet {
            saveSettings()
        }
    }
    
    private let db = Firestore.firestore()
    private var isLoading = false  // ✨ Prevent saving during load
    
    // Load settings from Firestore
    func loadSettings() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true  // ✨ Start loading
        
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            guard let self = self,
                  let data = snapshot?.data() else {
                self?.isLoading = false
                return
            }
            
            DispatchQueue.main.async {
                // ✨ Load without triggering save
                self.newChallengeEnabled = data["notif_newChallenge"] as? Bool ?? true
                self.upcomingMatchEnabled = data["notif_upcomingMatch"] as? Bool ?? true
                self.challengeEndedEnabled = data["notif_challengeEnded"] as? Bool ?? true
                
                self.isLoading = false  // ✨ Loading complete
                
                print("✅ Loaded: new=\(self.newChallengeEnabled), match=\(self.upcomingMatchEnabled), ended=\(self.challengeEndedEnabled)")
            }
        }
    }
    
    // Save settings to Firestore
    private func saveSettings() {
        // ✨ Don't save while loading
        guard !isLoading else {
            print("⏭️ Skipping save during load")
            return
        }
        
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let settings: [String: Any] = [
            "notif_newChallenge": newChallengeEnabled,
            "notif_upcomingMatch": upcomingMatchEnabled,
            "notif_challengeEnded": challengeEndedEnabled
        ]
        
        db.collection("users").document(userId).updateData(settings) { error in
            if let error = error {
                print("❌ Error saving: \(error)")
            } else {
                print("✅ Saved: new=\(self.newChallengeEnabled), match=\(self.upcomingMatchEnabled), ended=\(self.challengeEndedEnabled)")
            }
        }
    }
}
