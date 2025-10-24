import SwiftUI

struct PlayerProfileView: View {
    @State private var selectedTab: Tab = .profile
    @State private var showVideoUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                switch selectedTab {
                case .discovery: DiscoveryView()
                case .teams: TeamsView()
                case .challenge: ChallengeView()
                case .profile: PlayerProfileContentView()
                default: DiscoveryView()
                }
            }
            CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .fullScreenCover(isPresented: $showVideoUpload) {
            VideoUploadView()
        }
        // ✅ بعد نجاح إنشاء البوست: ارجعي لتبويب البروفايل وأغلقي شاشة الرفع
        .onReceive(NotificationCenter.default.publisher(for: .postCreated)) { _ in
            selectedTab = .profile
            showVideoUpload = false
        }
    }
}

// MARK: - Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showVideoUpload: Bool
    
    // MODIFIED: Use new BrandColors
    let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // MODIFIED: Subtle divider
                Divider().background(Color.black.opacity(0.1))
                
                // MODIFIED: Use new background color
                BrandColors.background
                    .frame(height: 85)
                    // MODIFIED: Use new shadow spec
                    .shadow(color: .black.opacity(0.08), radius: 12, y: -5)
            }
            
            HStack {
                TabButton(tab: .discovery, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .teams, selectedTab: $selectedTab, accentColor: accentColor)
                Spacer().frame(width: 80) // مساحة زر الوسط
                TabButton(tab: .challenge, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .profile, selectedTab: $selectedTab, accentColor: accentColor)
            }
            .padding(.horizontal, 30)
            .frame(height: 80)
            .padding(.top, 5)

            Button(action: { showVideoUpload = true }) {
                ZStack {
                    Circle()
                        // MODIFIED: Use new background
                        .fill(BrandColors.background)
                        .frame(width: 68, height: 68)
                        // MODIFIED: Use new shadow spec
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(accentColor)
                }
            }
            .buttonStyle(.plain)
            .offset(y: -30)
        }
        // MODIFIED: Add animation for tab scaling
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
            VStack(spacing: 4) {
                Image(systemName: tab.imageName)
                    .font(.system(size: 22)) // Slightly larger icon
                
                Text(tab.title)
                    // MODIFIED: Use new rounded font
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            // MODIFIED: Use new colors
            .foregroundColor(selectedTab == tab ? accentColor : BrandColors.darkGray.opacity(0.6))
            .frame(maxWidth: .infinity)
            // MODIFIED: Add scaling interaction
            .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
        }
    }
}
