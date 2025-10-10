import SwiftUI
import PhotosUI

struct PlayerSetupView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Model
    @State private var position: String = ""
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var location: String = ""
    
    // MARK: - Profile Picture States
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var profileImage: Image? = nil

    // MARK: - Position picker
    @State private var showPositionPicker: Bool = false
    private let positions = ["Attacker", "Midfielder", "Defender"]

    // MARK: - Navigation
    @State private var goToProfile = false

    // MARK: - Theme
    private let primary = Color(hexV: "#36796C")
    private let bg = Color(hexV: "#EFF5EC")

    // MARK: - Validation
    private var isFormValid: Bool {
        !position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !height.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    Text("Set up your profile")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    // MARK: - Profile Picture Picker (بالصورة الجديدة وعلامة الزائد)
                    ProfilePicturePicker(
                        selectedItem: $selectedItem,
                        profileImage: $profileImage,
                        primaryColor: primary
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)

                    // Position (button-like + wheel sheet)
                    fieldLabel("Position")
                    buttonLikeField {
                        HStack {
                            Text(position.isEmpty ? "Select position" : position)
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(position.isEmpty ? .gray : primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(primary.opacity(0.85))
                        }
                    } onTap: {
                        showPositionPicker = true
                    }
                    .sheet(isPresented: $showPositionPicker) {
                        PositionWheelPickerSheet(
                            positions: positions,
                            selection: $position,
                            showSheet: $showPositionPicker
                        )
                        .presentationDetents([.height(300)])
                        .presentationBackground(.white)
                        .presentationCornerRadius(28)
                    }

                    // Weight
                    fieldLabel("Weight")
                    roundedField {
                        TextField("", text: $weight)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Height
                    fieldLabel("Height")
                    roundedField {
                        TextField("", text: $height)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Location
                    fieldLabel("Location")
                    roundedField {
                        TextField("", text: $location)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Done
                    Button {
                        if isFormValid { goToProfile = true }
                    } label: {
                        Text("Done")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 6)
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.5)

                    Spacer(minLength: 20)
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
        .navigationDestination(isPresented: $goToProfile) {
            // PlayerProfileView()
        }
    }

    // MARK: - Helpers UI
    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Poppins", size: 14))
            .foregroundColor(.gray)
    }

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

    private func buttonLikeField<Content: View>(
        @ViewBuilder content: () -> Content,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
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
}

// -----------------------------------------------------------------------------------

// MARK: - Profile Picture Component
private struct ProfilePicturePicker: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var profileImage: Image?
    let primaryColor: Color
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            ZStack(alignment: .bottomTrailing) {
                // 1. Image or Placeholder
                if let image = profileImage {
                    // إذا تم اختيار صورة، اعرضها
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    // ✅ استخدام الصورة الرمادية المخصصة كـ Placeholder
                    Image("profile_placeholder") // 👈 يجب أن يكون هذا اسم الـ Imageset في Assets
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                }
                
                // 2. Edit Icon (علامة الزائد/Plus)
                Circle()
                    .fill(primaryColor)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "plus") // تم التغيير إلى علامة الزائد
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
            }
        }
        // 3. منطق التعامل مع اختيار الصورة (PhotosPicker)
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    if let uiImage = UIImage(data: data) {
                        profileImage = Image(uiImage: uiImage)
                    }
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------------

// MARK: - Wheel sheet for Position
private struct PositionWheelPickerSheet: View {
    let positions: [String]
    @Binding var selection: String
    @Binding var showSheet: Bool // تم تصحيح هذا السطر

    @State private var tempSelection: String = ""
    private let primary = Color(hexV: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your position")
                .font(.custom("Poppins", size: 18))
                .foregroundColor(primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

            Picker("", selection: $tempSelection) {
                ForEach(positions, id: \.self) { pos in
                    Text(pos).tag(pos)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 180)

            Button("Done") {
                selection = tempSelection
                showSheet = false
            }
            .font(.custom("Poppins", size: 18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary)
            .clipShape(Capsule())
            .padding(.bottom, 16)
            .safeAreaPadding(.bottom, 8)
        }
        .onAppear {
            tempSelection = selection.isEmpty ? (positions.first ?? "") : selection
        }
        .padding(.horizontal, 20)
    }
}
// -----------------------------------------------------------------------------------

// MARK: - Color hex init
extension Color {
    init(hexV: String) {
        let hexV = hexV.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexV).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexV.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17,
                            (int >> 4 & 0xF) * 17,
                            (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16,
                            int >> 8 & 0xFF,
                            int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24,
                            int >> 16 & 0xFF,
                            int >> 8 & 0xFF,
                            int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
