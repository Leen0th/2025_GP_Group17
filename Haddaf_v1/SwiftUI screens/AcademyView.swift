import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

// MARK: - Models

struct HaddafAcademy: Identifiable, Hashable {
    let id: String
    let name: String
    let logoURL: String?
    let city: String
    let street: String
    // Populated from subcollections
    var categories: [String] = []
    var coachUIDs: [String] = []
}

struct AcademyPlayerItem: Identifiable {
    let id: String
    let name: String
    let profilePicURL: String?
    let position: String?
    let status: String  // "accepted" | "pending"
    let coachUID: String
}

// MARK: - ViewModel

class HaddafAcademyViewModel: ObservableObject {
    @Published var academies: [HaddafAcademy] = []
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening() {
        listener?.remove()
        isLoading = true
        listener = db.collection("academies").addSnapshotListener { [weak self] snap, error in
            guard let self else { return }
            if let error = error {
                print("❌ AcademyView: \(error.localizedDescription)")
                self.isLoading = false; return
            }
            guard let docs = snap?.documents else { self.isLoading = false; return }

            Task {
                var list: [HaddafAcademy] = []
                for doc in docs {
                    let d = doc.data()
                    var academy = HaddafAcademy(
                        id: doc.documentID,
                        name: d["name"] as? String ?? "",
                        logoURL: d["logoURL"] as? String,
                        city: d["city"] as? String ?? "",
                        street: d["street"] as? String ?? ""
                    )
                    // Load categories
                    let catsSnap = try? await self.db.collection("academies").document(doc.documentID)
                        .collection("categories").getDocuments()
                    academy.categories = (catsSnap?.documents ?? []).map { $0.documentID }.sorted()
                    // Collect coaches from all categories
                    var coachSet = Set<String>()
                    for catDoc in catsSnap?.documents ?? [] {
                        let coaches = catDoc.data()["coaches"] as? [String] ?? []
                        coaches.forEach { coachSet.insert($0) }
                    }
                    academy.coachUIDs = Array(coachSet)

                    // If academy doc has no name field (ghost doc created by old code),
                    // try to fetch name from any coach's currentAcademy field
                    var resolvedName = academy.name
                    if resolvedName.isEmpty {
                        for coachUID in coachSet {
                            if let cDoc = try? await self.db.collection("users")
                                .document(coachUID).getDocument(),
                               let n = cDoc.data()?["currentAcademy"] as? String,
                               !n.isEmpty, n != "Unassigned" {
                                resolvedName = n
                                // Write the name into the academy doc so it shows next time
                                try? await self.db.collection("academies").document(doc.documentID)
                                    .setData(["name": n], merge: true)
                                break
                            }
                        }
                        academy = HaddafAcademy(
                            id: academy.id, name: resolvedName,
                            logoURL: academy.logoURL, city: academy.city, street: academy.street,
                            categories: academy.categories, coachUIDs: academy.coachUIDs
                        )
                    }

                    if !resolvedName.isEmpty { list.append(academy) }
                }

                // Merge academies with the same name — use the one with categories as canonical.
                // This handles the case where a ghost doc (no fields) and real doc both exist.
                var merged: [HaddafAcademy] = []
                var usedIDs: Set<String> = []
                for academy in list {
                    if usedIDs.contains(academy.id) { continue }
                    let sameNameDocs = list.filter {
                        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        == academy.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }
                    if sameNameDocs.count > 1 {
                        // Pick the one with the most categories (real doc)
                        let canonical = sameNameDocs.max(by: { $0.categories.count < $1.categories.count }) ?? academy
                        // Merge all coachUIDs from all duplicates
                        let allCoachUIDs = Array(Set(sameNameDocs.flatMap { $0.coachUIDs }))
                        var merged_a = canonical
                        merged_a.coachUIDs = allCoachUIDs
                        merged.append(merged_a)
                        sameNameDocs.forEach { usedIDs.insert($0.id) }
                    } else {
                        merged.append(academy)
                        usedIDs.insert(academy.id)
                    }
                }

                await MainActor.run {
                    self.academies = merged.sorted { $0.name < $1.name }
                    self.isLoading = false
                }
            }
        }
    }

    func stopListening() { listener?.remove(); listener = nil }
}

// MARK: - Main AcademyView

struct AcademyView: View {
    @EnvironmentObject var session: AppSession
    @StateObject private var vm = HaddafAcademyViewModel()
    @State private var searchText = ""
    @State private var selectedTab: AcademyTab = .saudiAcademies
    @State private var myAcademyName = ""
    @State private var myAcademyId = ""   // match by ID — more reliable than name
    private let accent = BrandColors.darkTeal

    enum AcademyTab: String, CaseIterable {
        case saudiAcademies = "Saudi Academies"
        case matchOpps      = "Match Opportunities"
    }

    private var filtered: [HaddafAcademy] {
        let s = searchText.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return vm.academies }
        return vm.academies.filter { $0.name.localizedCaseInsensitiveContains(s) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        academyTabButton(.saudiAcademies)
                        Divider().frame(height: 24).padding(.horizontal, 12)
                        academyTabButton(.matchOpps)
                    }
                    .padding(.vertical, 8).padding(.bottom, 4)

                    Group {
                        switch selectedTab {
                        case .saudiAcademies: academiesContent
                        case .matchOpps: matchOppsContent
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                vm.startListening()
                Task { await loadMyAcademy() }
            }
            .onDisappear { vm.stopListening() }
        }
    }

    private var academiesContent: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                Spacer(); ProgressView().tint(accent); Spacer()
            } else if vm.academies.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "building.2").font(.system(size: 56)).foregroundColor(.secondary.opacity(0.35))
                    Text("No academies yet").font(.system(size: 17, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(accent)
                    TextField("Search academy...", text: $searchText)
                        .font(.system(size: 16, design: .rounded)).tint(accent)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                }
                .padding(.vertical, 12).padding(.horizontal)
                .background(BrandColors.background).clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                .padding(.horizontal).padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 14) {
                        // Player's own academy — full width highlighted card (players only, not coaches)
                        // Use session role to check if user is a coach — more reliable than coachUIDs
                        let isCoachRole = session.role == "coach"
                        let myAcademy: HaddafAcademy? = isCoachRole ? nil : filtered.first(where: { isPlayerInAcademy($0) })
                        if !searchText.isEmpty || myAcademy == nil {
                            // Normal grid when searching or no personal academy
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                ForEach(filtered) { academy in
                                    NavigationLink(destination: AcademyDetailView(academy: academy)) {
                                        AcademyGridCard(academy: academy)
                                    }.buttonStyle(.plain)
                                }
                            }
                        } else {
                            // My academy full-width on top
                            if let mine = myAcademy {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("My Academy")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(accent).padding(.horizontal, 16)
                                    NavigationLink(destination: AcademyDetailView(academy: mine)) {
                                        AcademyListCard(academy: mine)
                                            .padding(.horizontal, 16)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18)
                                                    .stroke(accent.opacity(0.4), lineWidth: 1.5)
                                                    .padding(.horizontal, 16)
                                            )
                                    }.buttonStyle(.plain)
                                }.padding(.bottom, 4)

                                let others = filtered.filter { $0.id != mine.id }
                                if !others.isEmpty {
                                    Text("All Academies")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(accent)
                                        .padding(.horizontal, 16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                                        ForEach(others) { academy in
                                            NavigationLink(destination: AcademyDetailView(academy: academy)) {
                                                AcademyGridCard(academy: academy)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 100)
                }
            }
        }
    }

    private func loadMyAcademy() async {
        guard let uid = session.user?.uid else { return }
        let db = Firestore.firestore()
        let doc = try? await db.collection("users").document(uid).getDocument()
        let data = doc?.data() ?? [:]
        let name = data["currentAcademy"] as? String ?? ""
        var aId  = data["academyId"]      as? String ?? ""

        // Find the canonical academy ID (the one with categories) by name match.
        // This handles the case where the user's stored academyId points to a ghost doc.
        if !name.isEmpty {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let snap = try? await db.collection("academies").getDocuments()
            var bestId = aId
            var bestCatCount = -1
            for aDoc in snap?.documents ?? [] {
                let aName = (aDoc.data()["name"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard aName == trimmed else { continue }
                // Count categories
                let cats = try? await db.collection("academies").document(aDoc.documentID)
                    .collection("categories").getDocuments()
                let catCount = cats?.documents.count ?? 0
                if catCount > bestCatCount {
                    bestCatCount = catCount
                    bestId = aDoc.documentID
                }
            }
            if !bestId.isEmpty && bestId != aId {
                // Update user's academyId to point to the canonical doc
                try? await db.collection("users").document(uid)
                    .updateData(["academyId": bestId])
                aId = bestId
            }
        }

        await MainActor.run { myAcademyName = name; myAcademyId = aId }
    }

    private func isPlayerInAcademy(_ academy: HaddafAcademy) -> Bool {
        guard let uid = session.user?.uid else { return false }
        // Don't show My Academy for coaches
        if academy.coachUIDs.contains(uid) { return false }
        // Match by academyId first (most reliable)
        if !myAcademyId.isEmpty && academy.id == myAcademyId { return true }
        // Fallback: match by name (trimmed, lowercased) in case academyId not yet stored
        let trimmedMine = myAcademyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedAcad = academy.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedMine.isEmpty && !trimmedAcad.isEmpty && trimmedAcad == trimmedMine { return true }
        return false
    }

    private var matchOppsContent: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 52)).foregroundColor(accent.opacity(0.35))
                Text("Coming Soon").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(accent)
                Text("Match Opportunities will be available in the next sprint.")
                    .font(.system(size: 15, design: .rounded)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func academyTabButton(_ tab: AcademyTab) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue).font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(selectedTab == tab ? accent : accent.opacity(0.45))
                RoundedRectangle(cornerRadius: 1).frame(height: 2)
                    .foregroundColor(selectedTab == tab ? accent : .clear).frame(width: 120)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }
}

// MARK: - Academy Grid Card

struct AcademyGridCard: View {
    let academy: HaddafAcademy
    private let accent = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 8) {
            AcademyLogoView(logoURL: academy.logoURL, size: 60)
            Text(academy.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(accent).lineLimit(2).multilineTextAlignment(.center)
            if !academy.city.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10)).foregroundColor(accent.opacity(0.6))
                    Text(academy.city)
                        .font(.system(size: 11, design: .rounded)).foregroundColor(.secondary).lineLimit(1)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(BrandColors.background)
            .shadow(color: .black.opacity(0.07), radius: 8, y: 4))
    }
}

// MARK: - Academy List Card (for coach profile)

struct AcademyListCard: View {
    let academy: HaddafAcademy
    private let accent = BrandColors.darkTeal

    var body: some View {
        HStack(spacing: 14) {
            AcademyLogoView(logoURL: academy.logoURL, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(academy.name).font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(accent).lineLimit(1)
                if !academy.city.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12)).foregroundColor(accent.opacity(0.6))
                        Text(academy.city + (academy.street.isEmpty ? "" : " · \(academy.street)"))
                            .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(accent.opacity(0.4))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(BrandColors.background)
            .shadow(color: .black.opacity(0.07), radius: 8, y: 3))
    }
}

// MARK: - Academy Detail View

struct AcademyDetailView: View {
    let academy: HaddafAcademy
    @StateObject private var vm = AcademyDetailViewModel()
    @EnvironmentObject var session: AppSession
    private let accent = BrandColors.darkTeal

    // Logo editing state
    @State private var showLogoPicker = false
    @State private var selectedLogoImage: UIImage? = nil
    @State private var isUploadingLogo = false
    @State private var currentLogoURL: String? = nil

    private var isCoach: Bool {
        let uid = session.user?.uid ?? ""
        // 1. Check coachUIDs loaded from Firestore categories
        if academy.coachUIDs.contains(uid) { return true }
        // 2. vm.coaches list (loaded async)
        if vm.coaches.contains(where: { $0.0 == uid }) { return true }
        // 3. Fallback: session role is coach AND this academy matches their currentAcademy
        // This handles the case where the coach's UID is not yet in coachUIDs
        if session.role == "coach" { return true }
        return false
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        ZStack(alignment: .bottomTrailing) {
                            // Show newly picked logo immediately, fallback to stored URL
                            if let picked = selectedLogoImage {
                                Image(uiImage: picked).resizable().scaledToFill()
                                    .frame(width: 88, height: 88).clipShape(Circle())
                            } else {
                                AcademyLogoView(logoURL: currentLogoURL ?? academy.logoURL, size: 88)
                            }
                            if isCoach {
                                Button {
                                    showLogoPicker = true
                                } label: {
                                    ZStack {
                                        Circle().fill(accent).frame(width: 28, height: 28)
                                        if isUploadingLogo {
                                            ProgressView().tint(.white).scaleEffect(0.6)
                                        } else {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                        }
                                    }
                                    .shadow(color: accent.opacity(0.3), radius: 4, y: 2)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: 4)
                            }
                        }
                        Text(academy.name).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(accent)
                    }.padding(.top, 12)

                    // Coaches
                    if !vm.coaches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Coaches")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(vm.coaches, id: \.0) { uid, name, picURL in
                                        NavigationLink(destination: CoachProfileContentView(userID: uid)) {
                                            VStack(spacing: 6) {
                                                AsyncImage(url: URL(string: picURL ?? "")) { phase in
                                                    if case .success(let img) = phase {
                                                        img.resizable().scaledToFill().frame(width: 54, height: 54).clipShape(Circle())
                                                    } else {
                                                        Circle().fill(accent.opacity(0.1)).frame(width: 54, height: 54)
                                                            .overlay(Image(systemName: "person.fill").foregroundColor(accent))
                                                    }
                                                }
                                                Text(name).font(.system(size: 11, design: .rounded)).foregroundColor(.secondary).lineLimit(1).frame(width: 60)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 18)
                            }
                        }
                    }

                    // Categories
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            sectionTitle("Categories")
                            if isCoach {
                                NavigationLink(destination: AddCategoryView(
                                    academyId: academy.id,
                                    existingCategories: academy.categories,
                                    coachUID: session.user?.uid ?? "",
                                    onDone: { vm.load(academy: academy) }
                                )) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundColor(accent)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                        VStack(spacing: 10) {
                            ForEach(vm.categories, id: \.self) { cat in
                                NavigationLink(destination: CategoryPlayersView(
                                    academyId: academy.id,
                                    academyName: academy.name,
                                    category: cat,
                                    isCoach: isCoach,
                                    coachUID: session.user?.uid ?? ""
                                )) {
                                    HStack {
                                        Text(cat).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
                                            .padding(.horizontal, 14).padding(.vertical, 6).background(accent).clipShape(Capsule())
                                        Spacer()
                                        let count = vm.acceptedPlayerCounts[cat] ?? 0
                                        Text("\(count) players").font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(accent.opacity(0.5))
                                    }
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
                                }
                                .buttonStyle(.plain).padding(.horizontal, 18)
                            }
                        }
                    }
                    Spacer(minLength: 100)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.load(academy: academy)
            currentLogoURL = academy.logoURL
        }
        .fullScreenCover(isPresented: $showLogoPicker) {
            ImagePickerView(image: $selectedLogoImage).ignoresSafeArea()
        }
        .onChange(of: selectedLogoImage) { _, img in
            guard let img = img else { return }
            Task { await uploadLogo(img) }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(accent).padding(.horizontal, 18)
    }

    private func uploadLogo(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        await MainActor.run { isUploadingLogo = true }
        let ref = Storage.storage().reference()
            .child("academies/\(academy.id)/logo_\(UUID().uuidString).jpg")
        let meta = StorageMetadata(); meta.contentType = "image/jpeg"
        guard (try? await ref.putDataAsync(data, metadata: meta)) != nil,
              let url = try? await ref.downloadURL() else {
            await MainActor.run { isUploadingLogo = false }
            return
        }
        try? await Firestore.firestore().collection("academies").document(academy.id)
            .updateData(["logoURL": url.absoluteString])
        await MainActor.run {
            currentLogoURL = url.absoluteString
            isUploadingLogo = false
        }
    }
}

class AcademyDetailViewModel: ObservableObject {
    @Published var coaches: [(String, String, String?)] = []
    @Published var categories: [String] = []
    @Published var acceptedPlayerCounts: [String: Int] = [:]
    private let db = Firestore.firestore()

    func load(academy: HaddafAcademy) {
        Task {
            let catsSnap = try? await db.collection("academies").document(academy.id)
                .collection("categories").getDocuments()
            var cats: [String] = []
            var counts: [String: Int] = [:]
            var coachSet = Set<String>()
            for catDoc in catsSnap?.documents ?? [] {
                let cat = catDoc.documentID
                cats.append(cat)
                let coaches = catDoc.data()["coaches"] as? [String] ?? []
                coaches.forEach { coachSet.insert($0) }
                // Count only accepted players
                let playersSnap = try? await db.collection("academies").document(academy.id)
                    .collection("categories").document(cat).collection("players")
                    .whereField("status", isEqualTo: "accepted").getDocuments()
                counts[cat] = playersSnap?.documents.count ?? 0
            }
            // Load coach info
            var coachList: [(String, String, String?)] = []
            for uid in coachSet {
                if let doc = try? await db.collection("users").document(uid).getDocument(), let d = doc.data() {
                    let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
                    coachList.append((uid, name, d["profilePic"] as? String))
                }
            }
            await MainActor.run {
                self.categories = cats.sorted()
                self.acceptedPlayerCounts = counts
                self.coaches = coachList
            }
        }
    }
}

// MARK: - Add Category View

struct AddCategoryView: View {
    let academyId: String
    let existingCategories: [String]
    let coachUID: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategories: [String] = []
    @State private var isSaving = false
    // Loaded from Firestore so we always have the up-to-date list
    @State private var loadedExisting: [String] = []
    @State private var isLoadingCats = true
    private let accent = BrandColors.darkTeal
    private let allCats = ["U8", "U10", "U12", "U14", "U16"]
    private let db = Firestore.firestore()

    // Merge passed-in list with freshly loaded list from Firestore
    private var availableCats: [String] {
        let existing = Set(existingCategories + loadedExisting)
        return allCats.filter { !existing.contains($0) }
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Add Categories").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(accent).padding(.top, 20)

                if isLoadingCats {
                    ProgressView().tint(accent)
                } else if availableCats.isEmpty {
                    Text("All categories already added").font(.system(size: 15, design: .rounded)).foregroundColor(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(availableCats, id: \.self) { cat in
                            let sel = selectedCategories.contains(cat)
                            Button {
                                if sel { selectedCategories.removeAll { $0 == cat } }
                                else { selectedCategories.append(cat) }
                            } label: {
                                HStack {
                                    Text(cat).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(sel ? .white : accent)
                                    Spacer()
                                    Image(systemName: sel ? "checkmark.circle.fill" : "circle").foregroundColor(sel ? .white : .secondary)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(sel ? accent : BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 24)
                }

                if !availableCats.isEmpty {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(selectedCategories.isEmpty ? "Select categories" : "Add (\(selectedCategories.count))")
                                .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(selectedCategories.isEmpty ? accent.opacity(0.4) : accent).clipShape(Capsule())
                    }
                    .disabled(selectedCategories.isEmpty || isSaving).padding(.horizontal, 24)
                }
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load current categories directly from Firestore
            let snap = try? await db.collection("academies").document(academyId)
                .collection("categories").getDocuments()
            let cats = (snap?.documents ?? []).map { $0.documentID }
            await MainActor.run { loadedExisting = cats; isLoadingCats = false }
        }
    }

    private func save() async {
        isSaving = true
        for cat in selectedCategories {
            try? await db.collection("academies").document(academyId)
                .collection("categories").document(cat)
                .setData(["coaches": [coachUID], "createdAt": FieldValue.serverTimestamp()], merge: true)
        }
        await MainActor.run { isSaving = false; onDone(); dismiss() }
    }
}

// MARK: - Category Players View

struct CategoryPlayersView: View {
    let academyId: String
    let academyName: String
    let category: String
    let isCoach: Bool
    let coachUID: String

    @StateObject private var vm = CategoryPlayersViewModel()
    @State private var showInviteSheet = false
    @State private var playerToRemove: AcademyPlayerItem? = nil
    @State private var showRemoveConfirm = false
    @State private var pendingToCancel: AcademyPlayerItem? = nil
    @State private var showCancelConfirm = false
    private let accent = BrandColors.darkTeal

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(academyName).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                    Text(category).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(accent).clipShape(Capsule())
                }.padding(.top, 8).padding(.bottom, 16)

                if vm.isLoading {
                    Spacer(); ProgressView().tint(accent); Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Coaches section — only coaches who have added players show here
                            if !vm.coaches.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Coaches").font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(accent).padding(.horizontal, 18)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(vm.coaches, id: \.0) { uid, name, picURL in
                                                VStack(spacing: 4) {
                                                    AsyncImage(url: URL(string: picURL ?? "")) { phase in
                                                        if case .success(let img) = phase {
                                                            img.resizable().scaledToFill().frame(width: 48, height: 48).clipShape(Circle())
                                                        } else {
                                                            Circle().fill(accent.opacity(0.1)).frame(width: 48, height: 48)
                                                                .overlay(Image(systemName: "person.fill").foregroundColor(accent))
                                                        }
                                                    }
                                                    Text(name).font(.system(size: 10, design: .rounded)).foregroundColor(.secondary).lineLimit(1).frame(width: 56)
                                                }
                                            }
                                        }.padding(.horizontal, 18)
                                    }
                                }.padding(.bottom, 16)
                            }

                            // Add Player button for coach
                            if isCoach {
                                Button { showInviteSheet = true } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.badge.plus")
                                        Text("Invite Player")
                                    }
                                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(accent).clipShape(Capsule())
                                }
                                .buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 12)
                            }

                            // Accepted players
                            let accepted = vm.players.filter { $0.status == "accepted" }
                            let pending = vm.players.filter { $0.status == "pending" }

                            if !accepted.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Players (\(accepted.count))").font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(accent).padding(.horizontal, 18)
                                    ForEach(accepted) { p in
                                        playerRow(p, isPending: false)
                                    }
                                }.padding(.bottom, 12)
                            }

                            // Pending — only for coach
                            if isCoach && !pending.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Pending (\(pending.count))").font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(BrandColors.gold).padding(.horizontal, 18)
                                    ForEach(pending) { p in
                                        playerRow(p, isPending: true)
                                    }
                                }.padding(.bottom, 12)
                            }

                            if vm.players.isEmpty {
                                Text("No players yet").font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary).padding(.top, 20)
                            }
                        }.padding(.bottom, 100)
                    }
                }
            }

            // Remove confirm popup
            if showRemoveConfirm, let p = playerToRemove {
                confirmPopup(
                    title: "Remove Player?",
                    message: "\(p.name) will be removed from \(category).",
                    onNo: { showRemoveConfirm = false; playerToRemove = nil },
                    onYes: {
                        showRemoveConfirm = false
                        Task { await vm.removePlayer(academyId: academyId, category: category, playerUID: p.id, academyName: academyName, isPending: false); playerToRemove = nil }
                    }
                )
            }

            // Cancel invite popup
            if showCancelConfirm, let p = pendingToCancel {
                confirmPopup(
                    title: "Cancel Invitation?",
                    message: "Cancel the pending invitation for \(p.name)?",
                    onNo: { showCancelConfirm = false; pendingToCancel = nil },
                    onYes: {
                        showCancelConfirm = false
                        Task { await vm.removePlayer(academyId: academyId, category: category, playerUID: p.id, academyName: academyName, isPending: true); pendingToCancel = nil }
                    }
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load(academyId: academyId, category: category, isCoach: isCoach) }
        .sheet(isPresented: $showInviteSheet) {
            InvitePlayerSheet(
                academyId: academyId,
                category: category,
                coachUID: coachUID,
                existingPlayerUIDs: vm.players.map { $0.id },
                onDone: { showInviteSheet = false; vm.load(academyId: academyId, category: category, isCoach: isCoach) }
            )
            .presentationDetents([.large])
            .presentationBackground(BrandColors.background)
            .presentationCornerRadius(28)
        }
    }

    private func playerRow(_ p: AcademyPlayerItem, isPending: Bool) -> some View {
        HStack(spacing: 12) {
            // Tapping the photo/name area navigates to the player profile
            NavigationLink(destination: PlayerProfileContentView(userID: p.id)) {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: p.profilePicURL ?? "")) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                        } else {
                            Circle().fill(accent.opacity(0.1)).frame(width: 44, height: 44)
                                .overlay(Image(systemName: "person.fill").foregroundColor(accent))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        if let pos = p.position, !pos.isEmpty {
                            Text(pos).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isPending {
                Text("Pending").font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandColors.gold).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(BrandColors.gold.opacity(0.15)).clipShape(Capsule())
            }
            if isCoach {
                Button {
                    if isPending { pendingToCancel = p; showCancelConfirm = true }
                    else { playerToRemove = p; showRemoveConfirm = true }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18)).foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
        .padding(.horizontal, 18)
    }

    private func confirmPopup(title: String, message: String, onNo: @escaping () -> Void, onYes: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(title).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundColor(.primary)
                Text(message).font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                HStack(spacing: 16) {
                    Button("No") { onNo() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(BrandColors.darkGray)
                        .frame(maxWidth: .infinity).padding(.vertical, 12).background(BrandColors.lightGray).cornerRadius(12)
                    Button("Yes") { onYes() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.red).cornerRadius(12)
                }.padding(.top, 4)
            }
            .padding(24).frame(width: 320).background(BrandColors.background).cornerRadius(20).shadow(radius: 12)
        }
    }
}

class CategoryPlayersViewModel: ObservableObject {
    @Published var players: [AcademyPlayerItem] = []
    @Published var coaches: [(String, String, String?)] = []
    @Published var isLoading = true
    private let db = Firestore.firestore()

    func load(academyId: String, category: String, isCoach: Bool) {
        isLoading = true
        Task {
            // Load players — coach sees all, others see only accepted
            let playersSnap: QuerySnapshot?
            if isCoach {
                playersSnap = try? await db.collection("academies").document(academyId)
                    .collection("categories").document(category).collection("players")
                    .getDocuments()
            } else {
                playersSnap = try? await db.collection("academies").document(academyId)
                    .collection("categories").document(category).collection("players")
                    .whereField("status", isEqualTo: "accepted").getDocuments()
            }

            var list: [AcademyPlayerItem] = []
            // Track which coaches actually added players to this category
            var activeCoachUIDs = Set<String>()
            for doc in playersSnap?.documents ?? [] {
                let uid = doc.documentID
                let status = doc.data()["status"] as? String ?? "pending"
                let coachUID = doc.data()["coachUID"] as? String ?? ""
                if !coachUID.isEmpty { activeCoachUIDs.insert(coachUID) }
                if let ud = try? await db.collection("users").document(uid).getDocument(), let d = ud.data() {
                    let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
                    list.append(AcademyPlayerItem(id: uid, name: name,
                        profilePicURL: d["profilePic"] as? String,
                        position: d["position"] as? String,
                        status: status, coachUID: coachUID))
                }
            }

            // Only show coaches who have at least one player in this category
            var coachList: [(String, String, String?)] = []
            for uid in activeCoachUIDs {
                if let doc = try? await db.collection("users").document(uid).getDocument(), let d = doc.data() {
                    let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
                    coachList.append((uid, name, d["profilePic"] as? String))
                }
            }

            await MainActor.run {
                self.coaches = coachList
                self.players = list
                self.isLoading = false
            }
        }
    }

    func removePlayer(academyId: String, category: String, playerUID: String, academyName: String, isPending: Bool) async {
        // 1. Remove from academy
        try? await db.collection("academies").document(academyId)
            .collection("categories").document(category)
            .collection("players").document(playerUID).delete()

        if !isPending {
            // 2. Set currentAcademy to "Unassigned"
            // Only update fields the coach is allowed to write per Firestore rules:
            // ['teamId', 'teamName', 'academyName', 'currentAcademy']
            try? await db.collection("users").document(playerUID).updateData([
                "currentAcademy": "Unassigned"
            ])
            // 3. Send notification to player
            let notif: [String: Any] = [
                "userId": playerUID,
                "title": "🚫 Removed from Academy",
                "message": "You have been removed from the \(category) category of \(academyName).",
                "type": "removed_from_team",
                "isRead": false,
                "createdAt": FieldValue.serverTimestamp()
            ]
            try? await db.collection("notifications").addDocument(data: notif)
        }

        await MainActor.run {
            players.removeAll { $0.id == playerUID }
        }
    }
}

// MARK: - Invite Player Sheet

struct InvitePlayerSheet: View {
    let academyId: String
    let category: String
    let coachUID: String
    let existingPlayerUIDs: [String]
    let onDone: () -> Void

    @State private var searchText = ""
    @State private var results: [AcademyPlayerItem] = []
    @State private var selected: Set<String> = []
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var showAlreadyExistsAlert = false
    @State private var duplicatePlayerName = ""
    @Environment(\.dismiss) private var dismiss
    private let accent = BrandColors.darkTeal
    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search players...", text: $searchText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                            .onChange(of: searchText) { _, v in Task { await search(v) } }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2))
                    .padding(.horizontal, 18).padding(.vertical, 12)

                    ScrollView {
                        VStack(spacing: 8) {
                            if isSearching { ProgressView().tint(accent).padding() }
                            else {
                                ForEach(results) { p in
                                    let sel = selected.contains(p.id)
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: p.profilePicURL ?? "")) { phase in
                                            if case .success(let img) = phase {
                                                img.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                                            } else {
                                                Circle().fill(accent.opacity(0.1)).frame(width: 44, height: 44)
                                                    .overlay(Image(systemName: "person.fill").foregroundColor(accent))
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                                            if let pos = p.position, !pos.isEmpty {
                                                Text(pos).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Button {
                                            if existingPlayerUIDs.contains(p.id) {
                                                duplicatePlayerName = p.name
                                                showAlreadyExistsAlert = true
                                            } else if sel { selected.remove(p.id) }
                                            else { selected.insert(p.id) }
                                        } label: {
                                            Image(systemName: existingPlayerUIDs.contains(p.id) ? "checkmark.circle.fill" :
                                                    (sel ? "checkmark.circle.fill" : "plus.circle"))
                                                .font(.system(size: 26))
                                                .foregroundColor(existingPlayerUIDs.contains(p.id) ? .secondary :
                                                                    (sel ? BrandColors.actionGreen : accent))
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                                        .overlay(RoundedRectangle(cornerRadius: 14)
                                            .stroke(sel ? BrandColors.actionGreen.opacity(0.4) : .clear, lineWidth: 1.5)))
                                    .padding(.horizontal, 18)
                                }
                                if results.isEmpty && !searchText.isEmpty {
                                    Text("No players found").foregroundColor(.secondary).padding()
                                }
                            }
                        }.padding(.bottom, 80)
                    }

                    if !selected.isEmpty {
                        Button { Task { await sendInvitations() } } label: {
                            HStack {
                                if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text("Invite \(selected.count) Player(s)")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16).background(accent).clipShape(Capsule())
                        }
                        .padding(.horizontal, 18).padding(.bottom, 20).disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Invite Players — \(category)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(accent)
                }
            }
            .alert("Player Already in Category", isPresented: $showAlreadyExistsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(duplicatePlayerName) is already in this category.")
            }
        }
    }

    private func search(_ q: String) async {
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
        isSearching = true
        let snap = try? await db.collection("users").whereField("role", isEqualTo: "player").limit(to: 30).getDocuments()
        let ql = q.lowercased()
        let list = (snap?.documents ?? []).compactMap { doc -> AcademyPlayerItem? in
            let d = doc.data()
            let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
            guard name.lowercased().contains(ql) else { return nil }
            return AcademyPlayerItem(id: doc.documentID, name: name, profilePicURL: d["profilePic"] as? String,
                                     position: d["position"] as? String, status: "pending", coachUID: coachUID)
        }
        await MainActor.run { results = list; isSearching = false }
    }

    private func sendInvitations() async {
        isSaving = true

        // Ensure coachUID is in this category's coaches array
        do {
            try await db.collection("academies").document(academyId)
                .collection("categories").document(category)
                .setData(["coaches": FieldValue.arrayUnion([coachUID])], merge: true)
        } catch { print("❌ coaches update error: \(error)") }

        for uid in selected {
            // 1. Update academies/.../players with pending status
            do {
                try await db.collection("academies").document(academyId)
                    .collection("categories").document(category)
                    .collection("players").document(uid)
                    .setData([
                        "status": "pending",
                        "coachUID": coachUID,
                        "invitedAt": FieldValue.serverTimestamp()
                    ])
            } catch { print("❌ players write error: \(error)") }

            // 2. Create invitation doc
            var invRef: DocumentReference? = nil
            do {
                let invData: [String: Any] = [
                    "coachID": coachUID, "playerID": uid,
                    "teamName": "", "teamID": "",
                    "academyId": academyId, "category": category,
                    "status": "pending", "createdAt": FieldValue.serverTimestamp()
                ]
                invRef = try await db.collection("invitations").addDocument(data: invData)
            } catch { print("❌ invitation write error: \(error)") }

            // 3. Send notification with academy name
            do {
                // Try academy doc first, then coach's users doc as fallback
                var notifAcademyName = ""
                if let aDoc = try? await db.collection("academies").document(academyId).getDocument(),
                   let n = aDoc.data()?["name"] as? String, !n.isEmpty {
                    notifAcademyName = n
                }
                if notifAcademyName.isEmpty,
                   let cDoc = try? await db.collection("users").document(coachUID).getDocument(),
                   let n = cDoc.data()?["currentAcademy"] as? String, !n.isEmpty {
                    notifAcademyName = n
                }
                let notifMessage = notifAcademyName.isEmpty
                    ? "You've been invited to join the \(category) category."
                    : "You've been invited to join \(notifAcademyName) — \(category) category."
                let notif: [String: Any] = [
                    "userId": uid,
                    "title": "🏟️ Academy Invitation",
                    "message": notifMessage,
                    "type": "academy_invitation",
                    "teamName": notifAcademyName,
                    "academyId": academyId,
                    "category": category,
                    "invitationId": invRef?.documentID ?? "",
                    "isRead": false,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                try await db.collection("notifications").addDocument(data: notif)
                print("✅ notification sent to \(uid) — academy: \(notifAcademyName)")
            } catch { print("❌ notification write error: \(error)") }
        }
        await MainActor.run { isSaving = false; onDone() }
    }
}

// MARK: - Academy Setup Flow (First-Time from Coach Profile)

struct AcademySetupFlow: View {
    let academyName: String
    let coachUID: String
    let onDone: (HaddafAcademy?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var selectedCategories: [String] = []
    @State private var selectedLogo: UIImage? = nil
    @State private var showLogoPicker = false
    @State private var showCategoryPicker = false
    @State private var invitedMap: [String: Set<String>] = [:]
    @State private var searchText = ""
    @State private var searchResults: [AcademyPlayerItem] = []
    @State private var isSearching = false
    @State private var isSaving = false

    private let accent = BrandColors.darkTeal
    private let allCats = ["U8", "U10", "U12", "U14", "U16"]
    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                Group {
                    if step == 1 { selectStep }
                    else {
                        let idx = step - 2
                        if idx < selectedCategories.count {
                            inviteStep(for: selectedCategories[idx])
                        }
                    }
                }

                // Category picker — ZStack overlay (works in fullScreenCover)
                if showCategoryPicker {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .onTapGesture { withAnimation { showCategoryPicker = false } }
                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 0) {
                            HStack {
                                Text("Select Categories").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundColor(accent)
                                Spacer()
                                Button("Done") { withAnimation { showCategoryPicker = false } }
                                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(accent)
                            }.padding(.horizontal, 20).padding(.vertical, 16)
                            Divider()
                            ForEach(allCats, id: \.self) { cat in
                                Button {
                                    if selectedCategories.contains(cat) { selectedCategories.removeAll { $0 == cat } }
                                    else { selectedCategories.append(cat) }
                                } label: {
                                    HStack {
                                        Text(cat).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: selectedCategories.contains(cat) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22)).foregroundColor(selectedCategories.contains(cat) ? accent : .secondary)
                                    }.padding(.horizontal, 20).padding(.vertical, 14)
                                }.buttonStyle(.plain)
                                Divider().padding(.leading, 20)
                            }
                        }
                        .background(BrandColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 16).padding(.bottom, 32)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: showCategoryPicker)
            .navigationBarBackButtonHidden(true)
        }
        .fullScreenCover(isPresented: $showLogoPicker) {
            ImagePickerView(image: $selectedLogo).ignoresSafeArea()
        }
    }

    // STEP 1
    private var selectStep: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundColor(.secondary)
                            .padding(10).background(Circle().fill(Color(.systemGray5)))
                    }.buttonStyle(.plain)
                    Spacer()
                }.padding(.top, 4)

                Button { showLogoPicker = true } label: {
                    ZStack {
                        Circle().fill(accent.opacity(0.1)).frame(width: 90, height: 90)
                        if let img = selectedLogo {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 90, height: 90).clipShape(Circle())
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "camera.fill").font(.system(size: 22)).foregroundColor(accent)
                                Text("Logo").font(.system(size: 11, design: .rounded)).foregroundColor(accent)
                            }
                        }
                    }.overlay(Circle().stroke(accent.opacity(0.3), lineWidth: 1.5))
                }.buttonStyle(.plain)

                Text(academyName).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(accent).multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Text("Select categories").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Button { withAnimation { showCategoryPicker = true } } label: {
                        HStack {
                            Text(selectedCategories.isEmpty ? "Select categories" : selectedCategories.sorted().joined(separator: ", "))
                                .font(.system(size: 15, design: .rounded)).foregroundColor(selectedCategories.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                                selectedCategories.isEmpty ? Color.gray.opacity(0.2) : accent.opacity(0.4), lineWidth: 1.5)))
                    }.buttonStyle(.plain).padding(.horizontal, 24)

                    if !selectedCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedCategories.sorted(), id: \.self) { cat in
                                    HStack(spacing: 4) {
                                        Text(cat).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                                        Button { selectedCategories.removeAll { $0 == cat } } label: {
                                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.8))
                                        }.buttonStyle(.plain)
                                    }.padding(.horizontal, 12).padding(.vertical, 6).background(accent).clipShape(Capsule())
                                }
                            }.padding(.horizontal, 24)
                        }
                    }
                }

                Button {
                    guard !selectedCategories.isEmpty else { return }
                    withAnimation { step = 2 }
                } label: {
                    HStack(spacing: 6) {
                        Text("Continue").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(selectedCategories.isEmpty ? accent.opacity(0.4) : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(selectedCategories.isEmpty ? accent.opacity(0.1) : accent).clipShape(Capsule())
                }.disabled(selectedCategories.isEmpty).padding(.horizontal, 24)
            }.padding(.top, 16).padding(.bottom, 40)
        }
    }

    // STEP 2+
    private func inviteStep(for category: String) -> some View {
        let idx = step - 2
        let isLast = idx == selectedCategories.count - 1
        return VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Invite Players").font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                Text(category).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(accent)
            }.padding(.top, 16).padding(.bottom, 12)

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search players...", text: $searchText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                    .onChange(of: searchText) { _, v in Task { await search(v) } }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background).shadow(color: .black.opacity(0.05), radius: 6, y: 2))
            .padding(.horizontal, 18).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 8) {
                    if isSearching { ProgressView().tint(accent).padding() }
                    else {
                        ForEach(searchResults) { p in
                            let inv = invitedMap[category]?.contains(p.id) ?? false
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: p.profilePicURL ?? "")) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                                    } else {
                                        Circle().fill(accent.opacity(0.1)).frame(width: 44, height: 44)
                                            .overlay(Image(systemName: "person.fill").foregroundColor(accent))
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                                    if let pos = p.position, !pos.isEmpty {
                                        Text(pos).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    if inv { invitedMap[category]?.remove(p.id) }
                                    else { if invitedMap[category] == nil { invitedMap[category] = [] }; invitedMap[category]?.insert(p.id) }
                                } label: {
                                    Image(systemName: inv ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.system(size: 26)).foregroundColor(inv ? BrandColors.actionGreen : accent)
                                }.buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(inv ? BrandColors.actionGreen.opacity(0.4) : .clear, lineWidth: 1.5)))
                            .padding(.horizontal, 18)
                        }
                        if searchResults.isEmpty && !searchText.isEmpty {
                            Text("No players found").foregroundColor(.secondary).padding()
                        } else if searchText.isEmpty {
                            let count = invitedMap[category]?.count ?? 0
                            Text(count > 0 ? "\(count) player(s) selected" : "Search to invite players")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(count > 0 ? accent : .secondary).padding(.top, 30)
                        }
                    }
                }.padding(.bottom, 120)
            }

            HStack(spacing: 12) {
                Button { withAnimation { step = max(1, step - 1); searchText = ""; searchResults = [] } } label: {
                    HStack(spacing: 6) { Image(systemName: "arrow.left"); Text("Back") }
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 14).background(accent.opacity(0.1)).clipShape(Capsule())
                }.buttonStyle(.plain)

                Button {
                    if isLast { Task { await save() } }
                    else { withAnimation { step += 1; searchText = ""; searchResults = [] } }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text(isLast ? "Done" : "Continue")
                        if !isLast { Image(systemName: "arrow.right") }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(accent).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(isSaving)
            }.padding(.horizontal, 18).padding(.bottom, 32)
        }
    }

    private func search(_ q: String) async {
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { searchResults = []; return }
        isSearching = true
        let snap = try? await db.collection("users").whereField("role", isEqualTo: "player").limit(to: 30).getDocuments()
        let ql = q.lowercased()
        let list = (snap?.documents ?? []).compactMap { doc -> AcademyPlayerItem? in
            let d = doc.data()
            let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
            guard name.lowercased().contains(ql) else { return nil }
            return AcademyPlayerItem(id: doc.documentID, name: name, profilePicURL: d["profilePic"] as? String,
                                     position: d["position"] as? String, status: "pending", coachUID: coachUID)
        }
        await MainActor.run { searchResults = list; isSearching = false }
    }

    private func save() async {
        isSaving = true
        var logoURL: String? = nil
        if let img = selectedLogo, let data = img.jpegData(compressionQuality: 0.8) {
            let ref = Storage.storage().reference().child("academies/\(coachUID)/\(UUID().uuidString).jpg")
            let meta = StorageMetadata(); meta.contentType = "image/jpeg"
            if (try? await ref.putDataAsync(data, metadata: meta)) != nil {
                logoURL = try? await ref.downloadURL().absoluteString
            }
        }

        // Create/update academy doc
        let academiesSnap = try? await db.collection("academies")
            .whereField("name", isEqualTo: academyName).limit(to: 1).getDocuments()
        let academyRef: DocumentReference
        if let existing = academiesSnap?.documents.first {
            academyRef = existing.reference
            if let url = logoURL { try? await academyRef.updateData(["logoURL": url]) }
        } else {
            academyRef = db.collection("academies").document()
            var payload: [String: Any] = ["name": academyName, "createdAt": FieldValue.serverTimestamp()]
            if let url = logoURL { payload["logoURL"] = url }
            try? await academyRef.setData(payload)
        }

        // Create categories and invite players
        for category in selectedCategories {
            try? await academyRef.collection("categories").document(category)
                .setData(["coaches": [coachUID], "createdAt": FieldValue.serverTimestamp()], merge: true)

            for uid in invitedMap[category] ?? [] {
                try? await academyRef.collection("categories").document(category)
                    .collection("players").document(uid)
                    .setData(["status": "pending", "coachUID": coachUID, "invitedAt": FieldValue.serverTimestamp()])
                // Create invitation doc
                let invData: [String: Any] = [
                    "coachID": coachUID, "playerID": uid,
                    "teamName": academyName, "teamID": "",
                    "academyId": academyRef.documentID,
                    "category": category,
                    "status": "pending",
                    "createdAt": FieldValue.serverTimestamp()
                ]
                let invRef = try? await db.collection("invitations").addDocument(data: invData)
                // Send notification
                let notif: [String: Any] = [
                    "userId": uid,
                    "title": "🏟️ Academy Invitation",
                    "message": "You've been invited to join the \(category) category of \(academyName).",
                    "type": "academy_invitation",
                    "academyId": academyRef.documentID,
                    "category": category,
                    "invitationId": invRef?.documentID ?? "",
                    "isRead": false,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                try? await db.collection("notifications").addDocument(data: notif)
            }
        }

        // Update users doc — also store academyId for fast direct lookup
        try? await db.collection("users").document(coachUID).updateData([
            "currentAcademy": academyName,
            "academyId": academyRef.documentID,
            "updatedAt": FieldValue.serverTimestamp()
        ])

        // Build HaddafAcademy to pass back
        let createdAcademy = HaddafAcademy(
            id: academyRef.documentID,
            name: academyName,
            logoURL: logoURL,
            city: "", street: "",
            categories: selectedCategories,
            coachUIDs: [coachUID]
        )

        await MainActor.run { isSaving = false; onDone(createdAcademy) }
    }
}

// MARK: - Shared Logo View

struct AcademyLogoView: View {
    let logoURL: String?
    let size: CGFloat
    private let accent = BrandColors.darkTeal

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.1)).frame(width: size, height: size)
            if let urlStr = logoURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
                    } else {
                        Image(systemName: "building.2.fill").font(.system(size: size * 0.38)).foregroundColor(accent.opacity(0.7))
                    }
                }
            } else {
                Image(systemName: "building.2.fill").font(.system(size: size * 0.38)).foregroundColor(accent.opacity(0.7))
            }
        }
    }
}

// MARK: - Image Picker

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
