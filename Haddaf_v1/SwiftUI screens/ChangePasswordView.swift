import SwiftUI
import FirebaseAuth

struct ChangePasswordView: View {
    // MARK: - Theme
    // MODIFIED: BrandColors
    private let primary = BrandColors.darkTeal
    private let fieldBorder = Color.black.opacity(0.1)
    private let bg = BrandColors.backgroundGradientEnd

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
    
    // Check if passwords don't match (for inline error)
    private var passwordsDontMatch: Bool {
        !confirm.isEmpty && !newPass.isEmpty && newPass != confirm
    }
    // NEW: Check if new password exceeds 30 characters
    private var isNewPasswordTooLong: Bool {
        newPass.count > 30
    }


    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    Text("Change password")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
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
                                  contentType: .password)

                    VStack(alignment: .leading, spacing: 6) {
                        requirementRow("At least 8 characters, max 30", met: hasMinLength(newPass))
                        requirementRow("At least one uppercase letter (A-Z)", met: hasUppercase(newPass))
                        requirementRow("At least one lowercase letter (a-z)", met: hasLowercase(newPass))
                        requirementRow("At least one number (0-9)", met: hasDigit(newPass))
                        requirementRow("At least one special symbol", met: hasSpecialChar(newPass))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    if isNewPasswordTooLong {
                        Text("Password must be 30 characters or less.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }

                    // Confirm
                    fieldLabel("Confirm Password")
                    passwordField(text: $confirm,
                                  isShown: $showConfirm,
                                  contentType: .password)
                    
                    if passwordsDontMatch {
                        Text("Passwords do not match.")
                            // MODIFIED: Use new font
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.top, -14)
                    }

                    // Change Button
                    Button(action: changePassword) {
                        Text("Change")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(primary)
                            .clipShape(Capsule())
                            .shadow(color: primary.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.5)
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

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

    // MARK: - Password Validation
    private func isValidPassword(_ pass: String) -> Bool {
        guard pass.count >= 8 && pass.count <= 30 else { return false }
        let hasUpper   = pass.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLower   = pass.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit   = pass.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = pass.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        return hasUpper && hasLower && hasDigit && hasSpecial
    }

    private func hasMinLength(_ pass: String) -> Bool {
        pass.count >= 8 && pass.count <= 30
    }
    private func hasUppercase(_ pass: String) -> Bool { pass.range(of: "[A-Z]", options: .regularExpression) != nil }
    private func hasLowercase(_ pass: String) -> Bool { pass.range(of: "[a-z]", options: .regularExpression) != nil }
    private func hasDigit(_ pass: String) -> Bool { pass.range(of: "[0-9]", options: .regularExpression) != nil }
    private func hasSpecialChar(_ pass: String) -> Bool { pass.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil }

    // MARK: - UI Parts
    private func fieldLabel(_ title: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.gray)

            Text("*")
                .foregroundColor(.red)
                .font(.system(size: 14, weight: .medium, design: .rounded))
        }
    }

    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundColor(met ? primary : .gray.opacity(0.4))
            
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(met ? primary : .gray.opacity(0.6))
        }
    }

    /// Password field with eye toggle
    private func passwordField(text: Binding<String>,
                                   isShown: Binding<Bool>,
                                   contentType: UITextContentType = .password) -> some View {
        ZStack(alignment: .trailing) {
            Group {
                if isShown.wrappedValue {
                    TextField("", text: text)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.password)
                } else {
                    SecureField("", text: text)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.password)
                }
            }
            .font(.system(size: 16, design: .rounded))
            .foregroundColor(primary)
            .tint(primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(fieldBorder, lineWidth: 1))
            )

            Button { withAnimation { isShown.wrappedValue.toggle() } } label: {
                Image(systemName: isShown.wrappedValue ? "eye" : "eye.slash")
                    .foregroundColor(.gray)
                    .padding(.trailing, 12)
            }
        }
    }

    // MARK: - Logic
    // 1. Check if there is a logged-in user (currentUser).
    private func changePassword() {
        guard let user = Auth.auth().currentUser else {
            alertMessage = "No logged-in user found."
            showErrorAlert = true
            return
        }
        // 2. Validate that the New password matches the confirm password.
        guard newPass == confirm else {
            alertMessage = "New passwords do not match."
            showErrorAlert = true
            return
        }
        // 3. Validate password strength using isValidPassword().
        guard isValidPassword(newPass) else {
            alertMessage = "Password does not meet the requirements."
            showErrorAlert = true
            return
        }
        // 4. Retrieve the user’s email (needed for re-authentication).
        guard let email = user.email else {
            alertMessage = "Could not get user email."
            showErrorAlert = true
            return
        }

        // 5. Re-authenticate the user using the CURRENT password:
        let credential = EmailAuthProvider.credential(withEmail: email, password: current)
        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                alertMessage = "Current password is incorrect. Please make sure you entered it correctly."
                showErrorAlert = true
                return
            }
            // 6. Update password using user.updatePassword(to: newPass)
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

// MARK: - Centered Success Overlay
struct SuccessOverlay: View {
    let primary: Color
    let title: String
    let okAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .foregroundColor(primary)

                Text(title)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(BrandColors.darkGray) // MODIFIED

                Button(action: okAction) {
                    Text("OK")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
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
                    .fill(BrandColors.background)
            )
            .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        }
    }
}
