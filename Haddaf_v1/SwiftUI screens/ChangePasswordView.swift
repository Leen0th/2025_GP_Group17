import SwiftUI
import FirebaseAuth

// MARK: - Helper for HEX Colors
private func hex(_ hex: String) -> Color {
    let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: s).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch s.count {
    case 3: (a, r, g, b) = (255, (int>>8)*17, (int>>4 & 0xF)*17, (int & 0xF)*17)
    case 6: (a, r, g, b) = (255, int>>16, int>>8 & 0xFF, int & 0xFF)
    case 8: (a, r, g, b) = (int>>24, int>>16 & 0xFF, int>>8 & 0xFF, int & 0xFF)
    default: (a, r, g, b) = (255, 0, 0, 0)
    }
    return Color(.sRGB,
                 red: Double(r)/255,
                 green: Double(g)/255,
                 blue: Double(b)/255,
                 opacity: Double(a)/255)
}

// MARK: - Password Validation
private func isValidPassword(_ pass: String) -> Bool {
    guard pass.count >= 8 else { return false }
    let hasUpper   = pass.range(of: "[A-Z]", options: .regularExpression) != nil
    let hasLower   = pass.range(of: "[a-z]", options: .regularExpression) != nil
    let hasDigit   = pass.range(of: "[0-9]", options: .regularExpression) != nil
    let hasSpecial = pass.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
    return hasUpper && hasLower && hasDigit && hasSpecial
}

struct ChangePasswordView: View {
    // MARK: - Theme
    private let primary = hex("#36796C")
    private let fieldBorder = Color.black.opacity(0.25)
    private let bg = Color.white

    @Environment(\.dismiss) private var dismiss

    // MARK: - Fields
    @State private var current = ""
    @State private var newPass = ""
    @State private var confirm = ""

    // MARK: - Visibility
    @State private var showCurrent = false
    @State private var showNew = false
    @State private var showConfirm = false

    // MARK: - Alerts / Overlay
    @State private var alertMessage = ""
    @State private var showErrorAlert = false
    @State private var showSuccessOverlay = false

    // MARK: - Form Validity
    private var isFormValid: Bool {
        !current.isEmpty && !newPass.isEmpty && !confirm.isEmpty &&
        newPass == confirm && isValidPassword(newPass)
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // Title
                    Text("Change password")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Current
                    fieldLabel("Current Password")
                    passwordField(text: $current,
                                  isShown: $showCurrent,
                                  contentType: .password)

                    // New
                    fieldLabel("New Password")
                    passwordField(text: $newPass,
                                  isShown: $showNew,
                                  contentType: .password) // 👈 لا نستخدم .newPassword

                    // One-line red rules
                    if !newPass.isEmpty && !isValidPassword(newPass) {
                        Text("Password must be at least 8 characters and include uppercase and lowercase letters, a number, and a special symbol.")
                            .font(.custom("Poppins", size: 12))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .padding(.top, -6)
                    }

                    // Confirm
                    fieldLabel("Confirm Password")
                    passwordField(text: $confirm,
                                  isShown: $showConfirm,
                                  contentType: .password)

                    // Change Button
                    Button(action: changePassword) {
                        Text("Change")
                            .font(.custom("Poppins", size: 20))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(isFormValid ? primary : primary.opacity(0.4))
                            .clipShape(Capsule())
                    }
                    .disabled(!isFormValid)
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            // Success overlay (centered, transparent background)
            if showSuccessOverlay {
                SuccessOverlay(primary: primary,
                               title: "Password changed successfully",
                               okAction: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSuccessOverlay = false
                    }
                    dismiss()
                })
                .transition(.scale.combined(with: .opacity))
                .zIndex(1)
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
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("Change Password"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .navigationBarBackButtonHidden(true)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showSuccessOverlay)
    }

    // MARK: - UI Parts
    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Poppins", size: 18))
            .fontWeight(.semibold)
            .foregroundColor(.black.opacity(0.65))
    }

    /// Password/Text field with eye toggle and NO strong-password yellow overlay
    private func passwordField(text: Binding<String>,
                               isShown: Binding<Bool>,
                               contentType: UITextContentType = .password) -> some View {
        ZStack(alignment: .trailing) {
            Group {
                if isShown.wrappedValue {
                    TextField("", text: text)
                        .keyboardType(.asciiCapable)                 // 👈 يمنع الاقتراحات الغريبة
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.password)                  // 👈 لا نستخدم .newPassword
                } else {
                    SecureField("", text: text)
                        .keyboardType(.asciiCapable)                 // 👈
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.password)                  // 👈
                }
            }
            .font(.custom("Poppins", size: 16))
            .foregroundColor(primary)
            .tint(primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(fieldBorder, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                    )
            )

            Button { withAnimation { isShown.wrappedValue.toggle() } } label: {
                Image(systemName: isShown.wrappedValue ? "eye" : "eye.slash")
                    .foregroundColor(.gray)
                    .padding(.trailing, 12)
            }
        }
    }

    // MARK: - Logic
    private func changePassword() {
        guard let user = Auth.auth().currentUser else {
            alertMessage = "No logged-in user found."
            showErrorAlert = true
            return
        }

        guard newPass == confirm else {
            alertMessage = "New passwords do not match."
            showErrorAlert = true
            return
        }

        guard isValidPassword(newPass) else {
            alertMessage = "Password does not meet the requirements."
            showErrorAlert = true
            return
        }

        guard let email = user.email else {
            alertMessage = "Could not get user email."
            showErrorAlert = true
            return
        }

        // Re-authenticate using current password
        let credential = EmailAuthProvider.credential(withEmail: email, password: current)
        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                alertMessage = "Current password is incorrect: \(error.localizedDescription)"
                showErrorAlert = true
                return
            }

            user.updatePassword(to: newPass) { err in
                if let err = err {
                    alertMessage = "Failed to update password: \(err.localizedDescription)"
                    showErrorAlert = true
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSuccessOverlay = true
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ChangePasswordView() }
}

// MARK: - Centered Success Overlay
struct SuccessOverlay: View {
    let primary: Color
    let title: String
    let okAction: () -> Void

    var body: some View {
        ZStack {
            // Transparent dimmed background
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .foregroundColor(primary)

                Text(title)
                    .font(.custom("Poppins", size: 18))
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)

                Button(action: okAction) {
                    Text("OK")
                        .font(.custom("Poppins", size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 28)
            }
            .frame(maxWidth: 340)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        }
    }
}
