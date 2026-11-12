import SwiftUI
import TakaDeCore

/// Today's meals for a mess, one row per person, counted in half meals. Older days are a
/// tap away, and the month's meal rate opens below.
struct MealsCard: View {
    @Environment(AppModel.self) private var app
    let group: ExpenseGroup

    @State private var day = MealDay(Date())
    @State private var counts: [MemberID: Int] = [:]
    @State private var errorMessage: String?

    private var today: MealDay { MealDay(Date()) }

    var body: some View {
        SectionCard(title: "Meals") {
            DayNavigator(day: $day, latest: today)
        } content: {
            ForEach(group.members) { member in
                HStack(spacing: Spacing.s) {
                    Avatar(name: member.displayName, size: 36)
                    Text(verbatim: group.displayName(of: member.id))
                        .font(AppFont.body)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    MealStepper(halfMeals: counts[member.id] ?? 0) { set($0, for: member) }
                        .accessibilityLabel(Text("Meals for \(group.displayName(of: member.id))"))
                }
                .padding(.vertical, Spacing.xxs)
            }
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.owe)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
            }
            Divider().padding(.vertical, Spacing.xxs)
            NavigationLink { MessMonthView(group: group, month: day.messMonth) } label: {
                HStack {
                    Label("Meal rate and month", systemImage: "fork.knife")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted).accessibilityHidden(true)
                }
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.ink)
                .frame(minHeight: 44)
            }
        }
        .task(id: "\(day)-\(app.revision)") { await load() }
    }

    private func load() async {
        let meals = await app.mealCounts(in: group, month: day.messMonth)
        var byMember: [MemberID: Int] = [:]
        for meal in meals where meal.day == day { byMember[meal.memberID] = meal.halfMeals }
        counts = byMember
    }

    private func set(_ halfMeals: Int, for member: Member) {
        let before = counts[member.id]
        withAnimation(Motion.standard) { counts[member.id] = halfMeals }
        Task {
            do {
                try await app.save(MealCount(memberID: member.id, day: day, halfMeals: halfMeals), in: group)
                errorMessage = nil
            } catch {
                counts[member.id] = before
                errorMessage = String(localized: "That meal count wasn't saved. Try again.", bundle: .appLanguage)
            }
        }
    }
}

/// Back and forward a day, never past today. The date reads in the app's language.
private struct DayNavigator: View {
    @Binding var day: MealDay
    let latest: MealDay

    var body: some View {
        HStack(spacing: 0) {
            Button("Previous day", systemImage: "chevron.left") { move(-1) }
            Text(day.date(), format: .dateTime.day().month(.abbreviated))
                .font(AppFont.label)
                .foregroundStyle(Color.ink)
                .frame(minWidth: 64)
                .accessibilityLabel(Text(day.date(), format: .dateTime.weekday(.wide).day().month(.wide)))
            Button("Next day", systemImage: "chevron.right") { move(1) }
                .disabled(day >= latest)
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.medium))
        .foregroundStyle(Color.ink)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
    }

    private func move(_ days: Int) {
        let calendar = Calendar.current
        guard let moved = calendar.date(byAdding: .day, value: days, to: day.date(calendar: calendar)) else { return }
        let next = MealDay(moved, calendar: calendar)
        if next <= latest { day = next }
    }
}
