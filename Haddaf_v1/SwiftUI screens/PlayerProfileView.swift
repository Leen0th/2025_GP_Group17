import SwiftUI

// MARK: - Main Container View
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
    let accentColor = Color(hex: "#36796C")
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Divider()
                Color.white.frame(height: 85)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
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
            
            // ✅ زر الوسط: علامة + باللون الأخضر
            Button(action: { showVideoUpload = true }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 5)
                    
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(accentColor)   // نفس الأخضر
                }
            }
            .buttonStyle(.plain)
            .offset(y: -30)
        }
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
                Image(systemName: tab.imageName).font(.title2)
                Text(tab.title).font(.caption)
            }
            .foregroundColor(selectedTab == tab ? accentColor : .black.opacity(0.7))
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    PlayerProfileView()
}

