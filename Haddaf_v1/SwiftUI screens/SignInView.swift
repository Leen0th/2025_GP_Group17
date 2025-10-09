import SwiftUI

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isHidden: Bool = true // العين مقفلة افتراضيًا
    @State private var goToProfile = false   // 👈 الانتقال إلى PlayerProfile

    private let primary = Color(hex: "#36796C")
    private let bg = Color(hex: "#EFF5EC")

    // ✅ تحقق أن الحقول معبّاة
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // العنوان بالنص
                    Text("Sign In")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)

                    // البريد
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.custom("Poppins", size: 14))
                            .foregroundColor(.gray)

                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                            )
                    }

                    // كلمة المرور
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.custom("Poppins", size: 14))
                            .foregroundColor(.gray)

                        roundedField {
                            ZStack(alignment: .trailing) {
                                if isHidden {
                                    SecureField("", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.custom("Poppins", size: 16))
                                        .foregroundColor(primary)
                                        .tint(primary)
                                        .textContentType(.password)
                                        .padding(.trailing, 44)
                                } else {
                                    TextField("", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.custom("Poppins", size: 16))
                                        .foregroundColor(primary)
                                        .tint(primary)
                                        .textContentType(.password)
                                        .padding(.trailing, 44)
                                }

                                Button {
                                    withAnimation { isHidden.toggle() }
                                } label: {
                                    Image(systemName: isHidden ? "eye.slash" : "eye")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }

                    // Forgot password
                    HStack {
                        Spacer()
                        NavigationLink {
                            ForgotPasswordView()
                        } label: {
                            Text("Forgot password?")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(primary)
                        }
                    }
                    .padding(.top, 4)

                    // ✅ Log in button
                    Button {
                        if isFormValid {
                            goToProfile = true
                        }
                    } label: {
                        Text("Log in")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                    .disabled(!isFormValid) // تعطيل الزر حتى يعبي البيانات
                    .opacity(isFormValid ? 1.0 : 0.5)

                    // Sign up link
                    HStack(spacing: 6) {
                        Text("Don’t have an account?")
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(.gray)

                        NavigationLink {
                            SignUpView()
                        } label: {
                            Text("Sign Up")
                                .font(.custom("Poppins", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary)
                }
            }
        }
        .navigationBarBackButtonHidden(true)

        // 👇 بعد تسجيل الدخول يروح للبروفايل
        .navigationDestination(isPresented: $goToProfile) {
            PlayerProfileView()
        }
    }

    // MARK: - حقل بنفس التصميم
    private func roundedField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
    }
}

// MARK: - Hex Color
extension Color {
    init(hexValue: String) {
        let hexValue = hexValue.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexValue).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexValue.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17,
                                (int >> 4 & 0xF) * 17,
                                (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16,
                                int >> 8 & 0xFF,
                                int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24,
                                int >> 16 & 0xFF,
                                int >> 8 & 0xFF,
                                int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

#Preview {
    NavigationStack {
        SignInView()
    }
}


