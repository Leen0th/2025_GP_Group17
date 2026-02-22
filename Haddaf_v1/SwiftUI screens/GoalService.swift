import Foundation
import FirebaseFirestore

@MainActor
class GoalService: ObservableObject {
    static let shared = GoalService()

    @Published var goals: [PlayerGoal] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Listen to goals
    func startListening(for userId: String) {
        stopListening()
        isLoading = true
        listener = db.collection("playerGoals")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                self.isLoading = false
                self.goals = snap?.documents.compactMap { PlayerGoal.from(doc: $0) } ?? []
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Delete a goal
    func deleteGoal(goalId: String) async {
        try? await db.collection("playerGoals").document(goalId).delete()
    }

    // MARK: - Save / update a goal
    func saveGoal(userId: String, metric: MetricType, target: Int) async {
        // Check if a goal for this metric already exists
        if let existing = goals.first(where: { $0.metric == metric }) {
            // Update it
            try? await db.collection("playerGoals").document(existing.id).updateData([
                "targetCount": target,
                "status": GoalStatus.active.rawValue,
                "achievedAt": FieldValue.delete()
            ])
        } else {
            let goal = PlayerGoal(
                userId: userId,
                metric: metric,
                targetCount: target,
                status: .active,
                achievedAt: nil,
                createdAt: Date()
            )
            try? await db.collection("playerGoals").document(goal.id).setData(goal.asDictionary)
        }
    }

    // MARK: - Check goals after a new post
    /// Call this after a post is saved. Pass the detected stats from the video.
    static func checkGoalsAfterPost(userId: String, dribble: Int, pass: Int, shoot: Int) async {
        let db = Firestore.firestore()
        let snap = try? await db.collection("playerGoals")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: GoalStatus.active.rawValue)
            .getDocuments()

        guard let docs = snap?.documents else { return }

        for doc in docs {
            guard var goal = PlayerGoal.from(doc: doc) else { continue }
            let achieved: Bool
            switch goal.metric {
            case .dribble: achieved = dribble >= goal.targetCount
            case .pass:    achieved = pass    >= goal.targetCount
            case .shoot:   achieved = shoot   >= goal.targetCount
            }
            guard achieved else { continue }

            // Mark achieved in Firestore
            try? await db.collection("playerGoals").document(doc.documentID).updateData([
                "status": GoalStatus.achieved.rawValue,
                "achievedAt": Timestamp(date: Date())
            ])

            // Send notification
            await NotificationService.sendGoalAchievedNotification(
                userId: userId,
                metric: goal.metric.rawValue,
                target: goal.targetCount
            )
        }
    }
}
