// SharedAuthModels.swift
import SwiftUI
import Foundation
import FirebaseFirestore

// MARK: - Shared models used by SignUp/SignIn
struct ProfileDraft: Codable {
    let fullName: String
    let phone: String
    let role: String
    let dob: Date?
    let email: String
}

enum DraftStore {
    private static let key = "signup_profile_draft"

    static func save(_ draft: ProfileDraft) {
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> ProfileDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ProfileDraft.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Remote (Firestore) pending storage
enum PendingDraftStoreRemote {
    private static var col: CollectionReference { Firestore.firestore().collection("pendingSignups") }

    static func save(uid: String, draft: ProfileDraft) async throws {
        var data: [String: Any] = [
            "fullName": draft.fullName,
            "phone": draft.phone,
            "role": draft.role,
            "email": draft.email,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let d = draft.dob { data["dob"] = Timestamp(date: d) }
        try await col.document(uid).setData(data, merge: true)
    }

    static func load(uid: String) async throws -> ProfileDraft? {
        let snap = try await col.document(uid).getDocument()
        guard let d = snap.data() else { return nil }
        let fullName = d["fullName"] as? String ?? ""
        let phone    = d["phone"] as? String ?? ""
        let role     = d["role"] as? String ?? "player"
        let email    = d["email"] as? String ?? ""
        let dobTS    = d["dob"] as? Timestamp
        return ProfileDraft(fullName: fullName, phone: phone, role: role, dob: dobTS?.dateValue(), email: email)
    }

    static func clear(uid: String) async {
        do { try await col.document(uid).delete() } catch { /* ignore */ }
    }
}

// MARK: - Neutral Verify Email Modal (optional shared component)
public struct VerifyEmailModal: View {
    let title: String
    let message: String
    let leftTitle: String
    let rightTitle: String
    let onLeft: () -> Void
    let onRight: () -> Void
    let onDismiss: () -> Void
    var leftDisabled: Bool = false
    var errorText: String? = nil

    public init(
        title: String,
        message: String,
        leftTitle: String,
        rightTitle: String,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        leftDisabled: Bool = false,
        errorText: String? = nil
    ) {
        self.title = title
        self.message = message
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.onLeft = onLeft
        self.onRight = onRight
        self.onDismiss = onDismiss
        self.leftDisabled = leftDisabled
        self.errorText = errorText
    }

    public var body: some View {
        VStack {
            Spacer()
            ZStack(alignment: .topLeading) {
                VStack(spacing: 14) {
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    HStack(spacing: 16) {
                        Button(action: onLeft) {
                            Text(leftTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(leftDisabled ? .secondary : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(leftDisabled)

                        Button(action: onRight) {
                            Text(rightTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 12)

                    if let errorText, !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                    }
                    Spacer().frame(height: 8)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 10)
                )
            }
            Spacer()
        }
        .padding()
        .background(Color.clear)
    }
}
