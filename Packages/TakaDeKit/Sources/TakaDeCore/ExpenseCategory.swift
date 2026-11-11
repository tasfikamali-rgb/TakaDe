import Foundation

/// What an expense was for. Optional, and only used for icons and totals by category.
public enum ExpenseCategory: String, Codable, Sendable, CaseIterable {
    case food, groceries, transport, stay, rent, utilities, shopping, fun, health, other

    /// A first guess from the title, in English or Bengali, so most expenses need no
    /// extra tap. The person can always change it. Nil when nothing matches.
    public static func guess(from title: String) -> ExpenseCategory? {
        let text = title.lowercased()
        let words: [(ExpenseCategory, [String])] = [
            (.groceries, ["bazar", "bazaar", "grocer", "shwapno", "meena", "chaldal", "বাজার", "মুদি"]),
            (.food, ["biryani", "kacchi", "dinner", "lunch", "breakfast", "food", "restaurant", "cafe", "coffee", "tea", "snack", "pizza", "burger", "foodpanda", "খাবার", "বিরিয়ানি", "নাস্তা", "চা"]),
            (.transport, ["uber", "pathao", "cng", "rickshaw", "bus", "train", "launch", "taxi", "fuel", "petrol", "flight", "ticket", "ভাড়া গাড়ি", "রিকশা", "বাস", "ট্রেন"]),
            (.stay, ["hotel", "resort", "room", "airbnb", "হোটেল"]),
            (.rent, ["rent", "বাসা ভাড়া", "ভাড়া"]),
            (.utilities, ["electric", "current bill", "gas bill", "wifi", "internet", "water", "bill", "বিদ্যুৎ", "গ্যাস", "ইন্টারনেট", "বিল"]),
            (.shopping, ["shopping", "daraz", "clothes", "gift", "কেনাকাটা", "উপহার"]),
            (.fun, ["movie", "cinema", "game", "party", "concert", "সিনেমা"]),
            (.health, ["medicine", "pharmacy", "doctor", "hospital", "ওষুধ", "ডাক্তার"]),
        ]
        for (category, keys) in words where keys.contains(where: { text.contains($0) }) {
            return category
        }
        return nil
    }
}
