import SwiftUI

struct ChangePasswordView: View {
    // ألوان التطبيق
    private let primary = Color(hexv: "#36796C")
    private let fieldBorder = Color.black.opacity(0.25)
    private let bg = Color.white

    @Environment(\.dismiss) private var dismiss

    // الحقول
    @State private var current = ""
    @State private var newPass = ""
    @State private var confirm = ""

    // حالة العين لكل حقل
    @State private var showCurrent = false
    @State private var showNew = false
    @State private var showConfirm = false

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // العنوان بالنص
                    Text("Change password")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Current Password
                    fieldLabel("Current Password")
                    passwordField(text: $current, isShown: $showCurrent)

                    // New Password
                    fieldLabel("New Password")
                    passwordField(text: $newPass, isShown: $showNew)

                    // Confirm Password
                    fieldLabel("Confirm Password")
                    passwordField(text: $confirm, isShown: $showConfirm)

                    // زر التغيير
                    Button {
                        // TODO: تنفيذ تغيير كلمة المرور
                    } label: {
                        Text("Change")
                            .font(.custom("Poppins", size: 20))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 18)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
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
    }

    // MARK: - Components

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Poppins", size: 18))
            .fontWeight(.semibold)
            .foregroundColor(.black.opacity(0.65))
    }

    @ViewBuilder
    private func passwordField(text: Binding<String>, isShown: Binding<Bool>) -> some View {
        ZStack(alignment: .trailing) {
            Group {
                if isShown.wrappedValue {
                    TextField("", text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } else {
                    SecureField("", text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
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
}

// MARK: - HEX Color
extension Color {
    init(hexva: String) {
        let hexva = hexva.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexva).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexva.count {
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
        ChangePasswordView()
    }
}


