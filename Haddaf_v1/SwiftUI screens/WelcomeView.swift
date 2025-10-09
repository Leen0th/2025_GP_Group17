import SwiftUI

struct WelcomeView: View {
    private let primary = Color(hex: "#36796C")
    private let bg = Color(hex: "#EFF5EC")

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 35) {
                Spacer().frame(height: 100)

                // Logo
                Image("Haddaf_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)

                // Title
                Text("Let’s get started !")
                    .font(.custom("Poppins", size: 24))
                    .fontWeight(.medium)
                    .foregroundColor(primary)

                Spacer().frame(height: 40)

                // Buttons
                VStack(spacing: 22) {
                    // Sign In → SignInView
                    NavigationLink {
                        SignInView()
                    } label: {
                        Text("Sign In")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .cornerRadius(30)
                    }

                    // Sign Up → SignUpView
                    NavigationLink {
                        SignUpView()
                    } label: {
                        Text("Sign Up")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 30)
                                    .stroke(primary, lineWidth: 1)
                            )
                    }

                    HStack {
                        Rectangle().fill(Color.gray.opacity(0.35)).frame(height: 1)
                        Text("Or")
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(.gray)
                        Rectangle().fill(Color.gray.opacity(0.35)).frame(height: 1)
                    }

                    // Continue as guest → Profile (غيّر الاسم لصفحتك الفعلية)
                    NavigationLink {
                        PlayerProfileView()   // ← استبدلها باسم صفحة البروفايل عندك إن لزم
                    } label: {
                        Text("Continue as guest")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
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
        .navigationBarBackButtonHidden(true) // شاشة الترحيب بدون Back
    }
}
