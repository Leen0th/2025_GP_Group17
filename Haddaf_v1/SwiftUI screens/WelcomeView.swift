import SwiftUI
import FirebaseAuth

struct WelcomeView: View {
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd
    
    @EnvironmentObject var session: AppSession
    @State private var showMainApp = false
    
    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            
            VStack(spacing: 35) {
                Spacer().frame(height: 100)
                
                Image("Haddaf_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                
                Text("Let’s get started !")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(primary)
                
                Spacer().frame(height: 40)
                
                VStack(spacing: 22) {
                    NavigationLink { SignInView() } label: {
                        Text("Sign In")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .cornerRadius(30)
                            .shadow(color: primary.opacity(0.3), radius: 10, y: 5)
                    }
                    
                    NavigationLink { SignUpView() } label: {
                        Text("Sign Up")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BrandColors.background)
                            .cornerRadius(30)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 30)
                                    .stroke(primary, lineWidth: 1)
                            )
                    }
                    
                    HStack {
                        Rectangle().fill(Color.gray.opacity(0.35)).frame(height: 1)
                        Text("Or")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.gray)
                        Rectangle().fill(Color.gray.opacity(0.35)).frame(height: 1)
                    }
                    
                    // ⬇️ زر الضيف: تسجيل Anonymous فعليًا
                    Button {
                        Task {
                            do {
                                let result = try await Auth.auth().signInAnonymously()
                                await MainActor.run {
                                    session.user = result.user
                                    session.isGuest = true
                                    showMainApp = true
                                }
                            } catch {
                                // ممكن تستبدلها بتوست/تنبيه
                                print("Anonymous sign-in failed:", error.localizedDescription)
                            }
                        }
                    } label: {
                        Text("Continue as guest")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BrandColors.background)
                            .cornerRadius(30)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 30)
                                    .stroke(primary, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 40)
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showMainApp) {
            NavigationStack {
                // تقدر تغيّر الوجهة لاحقًا لـ MainTabs/Discovery.
                PlayerProfileView()
            }
        }
    }
}




