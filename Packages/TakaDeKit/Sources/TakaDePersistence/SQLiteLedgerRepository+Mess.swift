import Foundation
import GRDB
import TakaDeCore

extension SQLiteLedgerRepository: MessRepository {
    public func mealCounts(in group: GroupID, month: MessMonth) async throws -> [MealCount] {
        try await reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT member_id, day, half_meals FROM meal_count
                WHERE group_id = ? AND day LIKE ? ORDER BY day
                """, arguments: [group.description, "\(month.description)-%"])
            return rows.compactMap { row -> MealCount? in
                guard let member = UUID(uuidString: row["member_id"]),
                      let day = MealDay(row["day"] as String)
                else { return nil }
                return try? MealCount(memberID: MemberID(member), day: day, halfMeals: row["half_meals"])
            }
        }
    }

    public func save(_ meal: MealCount, in group: GroupID, actor: MemberID?) async throws {
        let snapshot = try JSONEncoder().encode(meal)
        try await writer.write { db in
            if meal.halfMeals == 0 {
                try db.execute(sql: "DELETE FROM meal_count WHERE group_id = ? AND member_id = ? AND day = ?",
                               arguments: [group.description, meal.memberID.description, meal.day.description])
            } else {
                try db.execute(sql: """
                    INSERT INTO meal_count (group_id, member_id, day, half_meals, updated_at) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(group_id, member_id, day) DO UPDATE SET half_meals = excluded.half_meals, updated_at = excluded.updated_at
                    """, arguments: [group.description, meal.memberID.description, meal.day.description, meal.halfMeals, Date()])
            }
            try Self.audit(db, AuditEvent(groupID: group, entity: .meal, entityID: meal.memberID.rawValue, action: .edited,
                                          actor: actor, snapshot: snapshot))
            try Self.enqueue(db, group: group, entity: .meal, body: snapshot)
        }
    }
}
