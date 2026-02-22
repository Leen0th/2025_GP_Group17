import SwiftUI
import FirebaseAuth

// MARK: - Pending deletion info
struct PendingGoalDelete {
    let goalId: String
    let metricName: String
    let isDismiss: Bool
}

// MARK: - Goal Tracking Section
struct GoalTrackingSection: View {
    let userId: String
    @Binding var pendingDelete: PendingGoalDelete?   // ← lifted to parent
    @StateObject private var service = GoalService.shared
    @State private var showSetGoalSheet = false

    private let primary = BrandColors.darkTeal

    private var unsetMetrics: [MetricType] {
        MetricType.allCases.filter { metric in
            !service.goals.contains(where: { $0.metric == metric })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            HStack {
                Text("My Goals")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                Spacer()
            }

            if service.isLoading {
                ProgressView().tint(primary).frame(maxWidth: .infinity)

            } else if service.goals.isEmpty {
                EmptyGoalStateView {
                    showSetGoalSheet = true
                }

            } else {
                VStack(spacing: 12) {
                    ForEach(service.goals) { goal in
                        GoalCard(
                            goal: goal,
                            userId: userId,
                            onRequestDelete: { isDismiss in
                                pendingDelete = PendingGoalDelete(
                                    goalId: goal.id,
                                    metricName: goal.metric.rawValue,
                                    isDismiss: isDismiss
                                )
                            }
                        )
                    }
                }
                if !unsetMetrics.isEmpty {
                    Button {
                        showSetGoalSheet = true
                    } label: {
                        Label("Set a Goal", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .onAppear { service.startListening(for: userId) }
        .sheet(isPresented: $showSetGoalSheet) {
            SetGoalSheet(userId: userId, availableMetrics: unsetMetrics)
        }
    }
}

// MARK: - Empty State
private struct EmptyGoalStateView: View {
    let onSet: () -> Void
    private let primary = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(primary.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "target")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(primary.opacity(0.6))
            }
            Text("No Goals Set Yet")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
            Text("Set a goal for your skills and track your improvement with each upload.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button(action: onSet) {
                Text("Set a Goal")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(primary)
                    .clipShape(Capsule())
                    .shadow(color: primary.opacity(0.3), radius: 8, y: 4)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Goal Card
private struct GoalCard: View {
    let goal: PlayerGoal
    let userId: String
    let onRequestDelete: (_ isDismiss: Bool) -> Void

    @State private var showUpdateSheet = false

    private let primary = BrandColors.darkTeal

    private var isAchieved: Bool { goal.status == .achieved }

    private var gradient: LinearGradient {
        switch goal.metric {
        case .dribble:
            return LinearGradient(colors: [BrandColors.turquoise.opacity(0.7), BrandColors.turquoise], startPoint: .leading, endPoint: .trailing)
        case .pass:
            return LinearGradient(colors: [BrandColors.teal.opacity(0.7), BrandColors.teal], startPoint: .leading, endPoint: .trailing)
        case .shoot:
            return LinearGradient(colors: [BrandColors.actionGreen.opacity(0.7), BrandColors.actionGreen], startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
            goalCardContent
            .sheet(isPresented: $showUpdateSheet) {
                SetGoalSheet(userId: userId, availableMetrics: [goal.metric], editingGoal: goal)
            }
        }

        private var goalCardContent: some View {
            VStack(alignment: .leading, spacing: 14) {
            // Row: icon + metric + badge + edit button
            HStack {
                ZStack {
                    Circle()
                        .fill(isAchieved ? Color.green.opacity(0.12) : primary.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: isAchieved ? "checkmark.seal.fill" : goal.metric.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isAchieved ? .green : primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.metric.rawValue)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                    Text("Target: \(goal.targetCount) per video")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isAchieved {
                    Text("Achieved!")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green)
                        .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Button {
                            showUpdateSheet = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 22))
                                .foregroundColor(primary.opacity(0.7))
                        }
                        Button {
                            onRequestDelete(false)
                        } label: {
                            Image(systemName: "trash.circle")
                                .font(.system(size: 22))
                                .foregroundColor(Color.red.opacity(0.7))
                        }
                    }
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                Text(isAchieved
                     ? "\(goal.metric.rawValue) goal reached in a video 🎉"
                     : "Active — reach \(goal.targetCount) \(goal.metric.rawValue) in one video")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(isAchieved ? .green : .secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BrandColors.lightGray).frame(height: 8)
                        Capsule()
                            .fill(isAchieved
                                  ? LinearGradient(colors: [.green.opacity(0.7), .green], startPoint: .leading, endPoint: .trailing)
                                  : gradient)
                            .frame(width: isAchieved ? geo.size.width : 0, height: 8)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isAchieved)
                    }
                }
                .frame(height: 8)
            }

            // Achieved date
            if isAchieved, let date = goal.achievedAt {
                Text("Achieved on \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // ── "Set a new goal?" prompt shown only when achieved ──
            if isAchieved {
                Divider()

                HStack(spacing: 0) {
                    Text("Set a new \(goal.metric.rawValue) goal?")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                    Spacer()
                    // NO — dismiss this goal card entirely
                    Button {
                        onRequestDelete(true)
                    } label: {
                        Text("No")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(BrandColors.lightGray)
                            .clipShape(Capsule())
                    }
                    .padding(.trailing, 8)

                    // YES — open edit sheet
                    Button {
                        showUpdateSheet = true
                    } label: {
                        Text("Yes")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: isAchieved ? Color.green.opacity(0.12) : Color.black.opacity(0.07), radius: 10, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isAchieved ? Color.green.opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Set / Edit Goal Sheet
// Holds per-metric target values inside the sheet
private struct MetricGoalEntry {
    var isSelected: Bool
    var target: Int = 0
}

struct SetGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let userId: String
    let availableMetrics: [MetricType]
    var editingGoal: PlayerGoal? = nil   // non-nil only when editing a single card

    @StateObject private var service = GoalService.shared
    @State private var entries: [MetricType: MetricGoalEntry] = [:]
    @State private var isSaving = false

    private let primary = BrandColors.darkTeal

    private var canSave: Bool {
        entries.values.contains(where: { $0.isSelected })
    }

    private var title: String {
        editingGoal != nil ? "Update Goal" : "Set Goals"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        if editingGoal != nil {
                            // ── Editing a single metric ──
                            let metric = editingGoal!.metric
                            SingleMetricEditor(
                                metric: metric,
                                entry: binding(for: metric)
                            )
                        } else {
                            // ── Setting goals for multiple metrics at once ──
                            Text("Select the metrics you want to set goals for")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)

                            ForEach(availableMetrics) { metric in
                                MultiMetricRow(
                                    metric: metric,
                                    entry: binding(for: metric)
                                )
                            }
                        }

                        Spacer(minLength: 20)

                        // Save button
                        Button {
                            isSaving = true
                            Task {
                                if let editing = editingGoal {
                                    let t = entries[editing.metric]?.target ?? editing.targetCount
                                    await service.saveGoal(userId: userId, metric: editing.metric, target: t)
                                } else {
                                    for metric in availableMetrics {
                                        guard let e = entries[metric], e.isSelected else { continue }
                                        await service.saveGoal(userId: userId, metric: metric, target: e.target)
                                    }
                                }
                                isSaving = false
                                dismiss()
                            }
                        } label: {
                            Group {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(editingGoal != nil ? "Update Goal" : "Save Goals")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(canSave ? primary : BrandColors.lightGray)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: canSave ? primary.opacity(0.3) : .clear, radius: 8, y: 4)
                        }
                        .disabled(!canSave || isSaving)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(primary)
                }
            }
            .onAppear { buildEntries() }
        }
    }

    // Pre-populate entries
    private func buildEntries() {
        if let editing = editingGoal {
            entries[editing.metric] = MetricGoalEntry(isSelected: true, target: editing.targetCount)
        } else {
            for metric in availableMetrics {
                entries[metric] = MetricGoalEntry(isSelected: false, target: 0)
            }
        }
    }

    private func binding(for metric: MetricType) -> Binding<MetricGoalEntry> {
        Binding(
            get: { entries[metric] ?? MetricGoalEntry(isSelected: false, target: 3) },
            set: { entries[metric] = $0 }
        )
    }
}

// MARK: - Row used when setting multiple goals at once
private struct MultiMetricRow: View {
    let metric: MetricType
    @Binding var entry: MetricGoalEntry
    private let primary = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 0) {
            // Tap the whole header row to toggle selection
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    entry.isSelected.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    // Checkbox
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(entry.isSelected ? primary : BrandColors.lightGray, lineWidth: 2)
                            .frame(width: 26, height: 26)
                        if entry.isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(primary)
                                .frame(width: 26, height: 26)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    Image(systemName: metric.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(entry.isSelected ? primary : .secondary)
                        .frame(width: 28)
                    Text(metric.rawValue)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(entry.isSelected ? BrandColors.darkGray : .secondary)
                    Spacer()
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Stepper — only visible when selected
            if entry.isSelected {
                Divider().padding(.horizontal, 16)
                HStack(spacing: 0) {
                    Text("Target per video")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 16) {
                        Button {
                            if entry.target > 0 { entry.target -= 1 }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(entry.target > 0 ? primary : BrandColors.lightGray)
                        }
                        Text("\(entry.target)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(primary)
                            .frame(minWidth: 28, alignment: .center)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.25), value: entry.target)
                        Button {
                            if entry.target < 5 { entry.target += 1 }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(entry.target < 5 ? primary : BrandColors.lightGray)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: entry.isSelected ? primary.opacity(0.1) : Color.black.opacity(0.05), radius: 10, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(entry.isSelected ? primary.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: entry.isSelected)
    }
}

// MARK: - Editor used when updating a single existing goal
private struct SingleMetricEditor: View {
    let metric: MetricType
    @Binding var entry: MetricGoalEntry
    private let primary = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: metric.iconName)
                    .font(.system(size: 22))
                    .foregroundColor(primary)
                Text(metric.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 8) {
                Text("Target per video")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                HStack(spacing: 24) {
                    Button {
                        if entry.target > 0 { entry.target -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(entry.target > 0 ? primary : BrandColors.lightGray)
                    }
                    Text("\(entry.target)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(primary)
                        .frame(minWidth: 60, alignment: .center)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: entry.target)
                    Button {
                        if entry.target < 5 { entry.target += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(entry.target < 5 ? primary : BrandColors.lightGray)
                    }
                }
                Text("actions in a single uploaded video")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }
}
