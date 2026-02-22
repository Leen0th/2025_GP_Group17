import Foundation
import FirebaseFirestore

// MARK: - Goal Status
enum GoalStatus: String, Codable {
    case active
    case achieved
}

// MARK: - Metric Type
enum MetricType: String, Codable, CaseIterable, Identifiable {
    case dribble = "Dribble"
    case pass = "Pass"
    case shoot = "Shoot"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dribble: return "figure.soccer"        // dribbling player
        case .pass:    return "arrow.up.forward"     // forward pass direction
        case .shoot:   return "circle.circle.fill"   // ball / shot on goal
        }
    }
}

// MARK: - Player Goal
struct PlayerGoal: Identifiable, Codable {
    var id: String = UUID().uuidString
    let userId: String
    let metric: MetricType
    var targetCount: Int
    var status: GoalStatus
    var achievedAt: Date?
    var createdAt: Date

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "metric": metric.rawValue,
            "targetCount": targetCount,
            "status": status.rawValue,
            "createdAt": Timestamp(date: createdAt)
        ]
        if let a = achievedAt { dict["achievedAt"] = Timestamp(date: a) }
        return dict
    }

    static func from(doc: QueryDocumentSnapshot) -> PlayerGoal? {
        let d = doc.data()
        guard
            let userId = d["userId"] as? String,
            let metricRaw = d["metric"] as? String,
            let metric = MetricType(rawValue: metricRaw),
            let target = d["targetCount"] as? Int,
            let statusRaw = d["status"] as? String,
            let status = GoalStatus(rawValue: statusRaw),
            let createdTS = d["createdAt"] as? Timestamp
        else { return nil }

        let achievedAt = (d["achievedAt"] as? Timestamp)?.dateValue()
        return PlayerGoal(
            id: doc.documentID,
            userId: userId,
            metric: metric,
            targetCount: target,
            status: status,
            achievedAt: achievedAt,
            createdAt: createdTS.dateValue()
        )
    }
}
