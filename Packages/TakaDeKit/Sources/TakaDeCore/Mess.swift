import Foundation

/// A group's kind. A mess is a shared flat or hostel where one manager keeps the books:
/// meals are counted every day and the month's bazar is split by meals eaten.
public enum GroupKind: String, Codable, Sendable, CaseIterable {
    case standard, mess
}

/// A calendar month, written "2026-11". Independent of time zones once made.
public struct MessMonth: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init?(year: Int, month: Int) {
        guard (1...12).contains(month), (2000...2200).contains(year) else { return nil }
        self.year = year
        self.month = month
    }

    public init(containing date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        year = parts.year ?? 2000
        month = parts.month ?? 1
    }

    public var description: String { String(format: "%04d-%02d", year, month) }

    public static func < (lhs: MessMonth, rhs: MessMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        MessMonth(containing: date, calendar: calendar) == self
    }

    public func contains(_ day: MealDay) -> Bool { day.year == year && day.month == month }

    /// The first moment of the month, for formatting its name.
    public func startDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    public func next() -> MessMonth {
        month == 12 ? MessMonth(year: year + 1, month: 1)! : MessMonth(year: year, month: month + 1)!
    }

    public func previous() -> MessMonth {
        month == 1 ? MessMonth(year: year - 1, month: 12)! : MessMonth(year: year, month: month - 1)!
    }
}

/// One calendar day, written "2026-11-05", so a meal count never shifts with the time zone.
public struct MealDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 2000
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var messMonth: MessMonth { MessMonth(year: year, month: month)! }

    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    public static func < (lhs: MealDay, rhs: MealDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// How many meals one person ate on one day, in half meals (a breakfast often counts as
/// half), so 3 means one and a half meals.
public struct MealCount: Hashable, Codable, Sendable {
    public let memberID: MemberID
    public let day: MealDay
    public let halfMeals: Int

    public init(memberID: MemberID, day: MealDay, halfMeals: Int) throws {
        guard (0...40).contains(halfMeals) else { throw MessError.invalidMealCount }
        self.memberID = memberID
        self.day = day
        self.halfMeals = halfMeals
    }
}

public enum MessError: Error, Equatable, Sendable {
    case invalidMealCount
    case noMeals
}

/// A mess month at a glance: bazar spent, meals eaten, and what each person's meals cost.
///
/// Each bazar expense is split by everyone's meals that month (largest-remainder rounding
/// per expense, so every poisha lands on someone and the totals match the ledger exactly
/// once the split is applied). Rent, bills and other fixed costs stay as recorded.
public struct MessMonthSummary: Equatable, Sendable {
    public let month: MessMonth
    public let halfMeals: [MemberID: Int]
    public let bazarTotal: Money
    public let mealCost: [MemberID: Money]
    /// Bazar expenses this month, which "Split bazar by meals" re-splits.
    public let bazarExpenses: [Expense]

    public var totalHalfMeals: Int { halfMeals.values.reduce(0, +) }

    /// Cost of one meal, rounded down to the poisha, for display. The split itself uses
    /// exact shares, not this rounded rate.
    public var mealRate: Money? {
        guard totalHalfMeals > 0 else { return nil }
        return Money(minorUnits: bazarTotal.minorUnits * 2 / Int64(totalHalfMeals), currency: bazarTotal.currency)
    }

    /// The split every bazar expense gets: shares by half meals eaten this month.
    public var mealSplitRule: SplitRule? {
        let weights = halfMeals.filter { $0.value > 0 }
        return weights.isEmpty ? nil : .shares(weights)
    }

    /// Bazar is any expense in the Bazar category dated in this month.
    public static func isBazar(_ expense: Expense, in month: MessMonth, calendar: Calendar = .current) -> Bool {
        expense.deletedAt == nil && expense.category == .groceries && month.contains(expense.occurredAt, calendar: calendar)
    }

    public init(month: MessMonth, members: [MemberID], meals: [MealCount], expenses: [Expense], currency: Currency, calendar: Calendar = .current) throws {
        self.month = month
        var counts = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        for meal in meals where month.contains(meal.day) && counts[meal.memberID] != nil {
            counts[meal.memberID, default: 0] += meal.halfMeals
        }
        halfMeals = counts
        let bazar = expenses.filter { Self.isBazar($0, in: month, calendar: calendar) && $0.total.currency == currency }
        bazarExpenses = bazar
        let total = try bazar.map(\.total).sum(in: currency)
        bazarTotal = total

        var cost = Dictionary(uniqueKeysWithValues: members.map { ($0, Money.zero(currency)) })
        let weights = counts.filter { $0.value > 0 }
        if !weights.isEmpty {
            for expense in bazar {
                let split = try SplitCalculator.allocate(expense.total, by: .shares(weights))
                for (member, share) in split.shares {
                    cost[member] = try cost[member, default: .zero(currency)].adding(share)
                }
            }
        }
        mealCost = cost
    }
}
