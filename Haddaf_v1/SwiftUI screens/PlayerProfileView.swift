
import SwiftUI

struct PlayerProfileView: View {
    @EnvironmentObject var session: AppSession
    @State private var selectedTab: Tab = .discovery
    @State private var showVideoUpload = false
    
    var body: some View {
            ZStack(alignment: .bottom) {
                VStack {
                    switch selectedTab {
                    case .discovery: DiscoveryView()
                    case .teams: TeamsView()
                    case .challenge: ChallengeView()
                        // If the user is a guest, show the gate instead of the real profile.
                    case .profile: if session.isGuest {
                        GuestProfileGateView()
                    } else {
                        PlayerProfileContentView()
                    }
                    default: DiscoveryView()
                    }
                }
                CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .fullScreenCover(isPresented: $showVideoUpload) {
                VideoUploadView()
            }
        // After a post is created, switch to the Profile tab and close the upload screen.
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
            Button(action: { showVideoUpload = true }) {
                ZStack {
                    Circle()
                        .fill(BrandColors.background)
                       
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                    Image(systemName: "video.badge.plus")
                        
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(accentColor)
                }
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
