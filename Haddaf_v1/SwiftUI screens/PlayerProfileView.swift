import SwiftUI
import FirebaseFirestore

extension Notification.Name {
    static let userSignedIn = Notification.Name("userSignedIn")
}

struct PlayerProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession
    @State private var selectedTab: Tab = .discovery
    @State private var showVideoUpload = false
    @State private var showAuthSheet = false
    @State private var showLineupBuilder = false
    
    // Track if the view has already appeared
    @State private var hasAppeared = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                switch selectedTab {
                case .discovery:
                    DiscoveryView()
                case .teams:
                    TeamsView()
                case .challenge:
                    ChallengeView()
                case .lineupBuilder:
                    LineupBuilderView()
                case .profile:
                    if session.isGuest {
                        NavigationStack {
                            GuestProfileGateView()
                        }
                    } else if session.role == "coach" {
                        // If user is a coach, show the Coach Profile
                        CoachProfileContentView()
                    } else {
                        // Otherwise, show the Player Profile
                        PlayerProfileContentView()
                    }
                default:
                    DiscoveryView()
                }
            }
            .zIndex(0)  // Main content at bottom layer
                        
            CustomTabBar(
                selectedTab: $selectedTab,
                showVideoUpload: $showVideoUpload,
                showAuthSheet: $showAuthSheet
            )
            
            if showAuthSheet {
                AuthPromptSheet(isPresented: $showAuthSheet)
                    .animation(.easeInOut, value: showAuthSheet)
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .fullScreenCover(isPresented: $showVideoUpload) {
            VideoUploadView()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)

        .onReceive(NotificationCenter.default.publisher(for: .postCreated)) { _ in
            selectedTab = .profile
            showVideoUpload = false
        }
        .onAppear {
            // Force Discovery tab on first real appearance
            if !hasAppeared {
                selectedTab = .discovery
                hasAppeared = true
            }
            
            // Refresh role whenever we appear to ensure the UI matches the account
            if let uid = session.user?.uid {
                Task {
                    let role = await fetchRole()
                    await MainActor.run {
                        session.role = role
                    }
                }
            }
        }
        .onChange(of: session.user) { oldUser, newUser in
            if let user = newUser {
                Task {
                    session.role = await fetchRole()
                }
            } else {
                session.role = nil
                selectedTab = .discovery
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userSignedIn)) { note in
            if let role = note.userInfo?["role"] as? String {
                if role == "coach" {
                    selectedTab = .discovery
                } else {
                    selectedTab = .profile
                }
            }
        }
    }

    private func fetchRole() async -> String? {
        guard let uid = session.user?.uid else { return nil }
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .getDocument()
            return doc.data()?["role"] as? String
        } catch {
            print("Error fetching role: \(error)")
            return nil
        }
    }
}



// MARK: - Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showVideoUpload: Bool
    @Binding var showAuthSheet: Bool
    
    @EnvironmentObject var session: AppSession
    
    // MODIFIED:new BrandColors
    let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack {

            VStack(spacing: 0) {
                Divider().background(Color.black.opacity(0.1))
                
                BrandColors.background
                    .frame(height: 80)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: -5)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            


            HStack {
                TabButton(tab: .discovery, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .teams, selectedTab: $selectedTab, accentColor: accentColor)
                Spacer().frame(width: 80)
                TabButton(tab: .challenge, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .profile, selectedTab: $selectedTab, accentColor: accentColor)
            }
            .padding(.horizontal, 20)
            .frame(height: 80)
            .frame(maxHeight: .infinity, alignment: .bottom)
            Button(action: {
                if session.isGuest {
                    // Guests always see the Auth Sheet regardless of the icon shown
                    showAuthSheet = true
                } else if session.role == "coach" {
                    selectedTab = .lineupBuilder
                } else {
                    // Players (and theoretically guests if they weren't caught above)
                    // see the upload flow
                    showVideoUpload = true
                }
            }) {
                ZStack {
                    Circle()
                        .fill(BrandColors.background)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                    // Show sportscourt ONLY if verified coach.
                    // Guests and Players see video.badge.plus
                    Image(systemName: session.role == "coach" ? "sportscourt" : "video.badge.plus")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(
                            // Highlight if active
                            ((session.role == "coach" && selectedTab == .lineupBuilder) ||
                             (session.role != "coach" && showVideoUpload))
                            ? BrandColors.darkTeal
                            : .gray
                        )
                }
                .animation(.easeInOut(duration: 0.2), value: selectedTab)


            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity, alignment: .bottom)
            
            .offset(y: -35)
            
        }
        
        .frame(height: 120)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
    }
}

// MARK: - Tab Bar Helper
fileprivate struct TabButton: View {
    let tab: Tab
    @Binding var selectedTab: Tab
    let accentColor: Color
    
    var body: some View {
        Button(action: { selectedTab = tab }) {
            VStack(spacing: 5) {
                Image(systemName: selectedTab == tab ? tab.selectedImageName : tab.imageName)
                    .font(.system(size: 26, weight: .medium))
                    .frame(height: 28)
                
              
                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(selectedTab == tab ? accentColor : BrandColors.darkGray.opacity(0.6))
            .frame(maxWidth: .infinity)
            .scaleEffect(selectedTab == tab ? 1.05 : 1.0)
        }
    }
}
