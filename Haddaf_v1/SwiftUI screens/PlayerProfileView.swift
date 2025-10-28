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
// MARK: - Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showVideoUpload: Bool
    
    // MODIFIED: Use new BrandColors
    let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack { // <-- 1. Remove alignment: .top

            // 2. BACKGROUND: Make it fill the bottom
            // This VStack is the visual bar.
            VStack(spacing: 0) {
                // MODIFIED: Subtle divider
                Divider().background(Color.black.opacity(0.1))
                
                // MODIFIED: Use new background color
                BrandColors.background
                    // Give it a height *above* the safe area
                    .frame(height: 80) // <-- NOTE: This is the visible bar height now
            }
            // MODIFIED: Use new shadow spec, applied to the VStack
            .shadow(color: .black.opacity(0.08), radius: 12, y: -5)
            .frame(maxHeight: .infinity, alignment: .bottom) // <-- Align VStack to bottom
            .ignoresSafeArea() // <-- **** KEY: Make background fill safe area
            

            // 3. BUTTONS: Align to bottom, but add padding for safe area
            HStack {
                TabButton(tab: .discovery, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .teams, selectedTab: $selectedTab, accentColor: accentColor)
                // ✅ 3. WIDER SPACER: Increased from 80 to 90
                Spacer().frame(width: 80) // You had 80, this might need to be 90
                TabButton(tab: .challenge, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .profile, selectedTab: $selectedTab, accentColor: accentColor)
            }
            // ✅ 3. LESS PADDING: Reduced from 30 to 20
            .padding(.horizontal, 20)
            .frame(height: 80) // This height is for the buttons themselves
            // .padding(.top, 10) // <-- REMOVE this
            .frame(maxHeight: .infinity, alignment: .bottom) // <-- Align HStack to bottom
            // Add padding to keep buttons out of the home indicator area
            // .padding(.bottom, 5) // <-- Adjust this value as needed


            // 4. MIDDLE BUTTON: Align to bottom, then offset
            Button(action: { showVideoUpload = true }) {
                ZStack {
                    Circle()
                        // MODIFIED: Use new background
                        .fill(BrandColors.background)
                        // ✅ 3. LARGER MIDDLE BUTTON: Increased from 68 to 72
                        .frame(width: 72, height: 72)
                        // MODIFIED: Use new shadow spec
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

                    Image(systemName: "video.badge.plus")
                         // ✅ 3. LARGER MIDDLE ICON: Increased from 28 to 32
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(accentColor)
                }
            }
            .buttonStyle(.plain)
            // Align to bottom, *then* offset it up
            .frame(maxHeight: .infinity, alignment: .bottom)
             // ✅ 3. ADJUSTED OFFSET: This offset is now relative to the bottom edge
            .offset(y: -35)
            
        }
        // Give the whole ZStack a larger, fixed height to contain everything
        .frame(height: 120)
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
            VStack(spacing: 5) { // Increased spacing slightly
                
                // ✅ 1. HIGH CONTRAST: Use .fill for the selected icon
                Image(systemName: selectedTab == tab ? tab.selectedImageName : tab.imageName)
                    // ✅ 2. LARGER ICON: Increased from 22 to 26
                    .font(.system(size: 26, weight: .medium))
                    // Add a minimum frame height to stop layout jumps
                    .frame(height: 28)
                
                // ✅ 2. LARGER TITLE: Increased from 10 to 12 and made bolder
                Text(tab.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            // MODIFIED: Use new colors
            .foregroundColor(selectedTab == tab ? accentColor : BrandColors.darkGray.opacity(0.6))
            .frame(maxWidth: .infinity)
            // MODIFIED: Add scaling interaction
            .scaleEffect(selectedTab == tab ? 1.05 : 1.0) // Reduced scale effect slightly
        }
    }
}
