import SwiftUI
import TakaDeCore

/// A mess month: the meal rate up top, each person's meals and what they cost, and one
/// action that re-splits the month's bazar by meals eaten.
struct MessMonthView: View {
    @Environment(AppModel.self) private var app
    let group: ExpenseGroup
    @State var month: MessMonth

    @State private var summary: MessMonthSummary?
    @State private var confirmingSplit = false
    @State private var errorMessage: String?
    @State private var splitDone = 0

    private var current: MessMonth { MessMonth(containing: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                monthNavigator
                if let summary {
                    rateCard(summary)
                    SectionCard(title: "Each person") {
                        ForEach(group.members) { member in
                            MessMemberRow(group: group, member: member, summary: summary)
                        }
                    }
                    actions(summary)
                }
                if let errorMessage {
                    Text(verbatim: errorMessage).font(AppFont.label).foregroundStyle(Color.owe)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.m)
            .readableWidth()
        }
        .background(Color.canvas)
        .navigationTitle("Mess month")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let summary {
                    ShareLink(item: MessMonthText.make(summary, group: group)) {
                        Label("Share the month", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .confirmationDialog(Text("Split this month's bazar by meals?"), isPresented: $confirmingSplit, titleVisibility: .visible) {
            Button("Split by meals", action: applySplit)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each bazar expense this month is shared by how many meals each person ate. The change shows in History, and you can edit any expense afterwards.")
        }
        .sensoryFeedback(.success, trigger: splitDone)
        .task(id: "\(month)-\(app.revision)") { await load() }
    }

    private var monthNavigator: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") { month = month.previous() }
            Spacer()
            Text(month.startDate(), format: .dateTime.month(.wide).year())
                .font(AppFont.headline)
                .foregroundStyle(Color.ink)
            Spacer()
            Button("Next month", systemImage: "chevron.right") { month = month.next() }
                .disabled(month >= current)
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.medium))
        .foregroundStyle(Color.ink)
        .frame(minHeight: 44)
    }

    private func rateCard(_ summary: MessMonthSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Meal rate").font(AppFont.label).foregroundStyle(Color.inkMuted)
            if let rate = summary.mealRate {
                AmountText(money: rate, size: .balance)
            } else {
                Text("No meals counted yet").font(AppFont.headline).foregroundStyle(Color.ink)
            }
            HStack(spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Bazar").font(AppFont.caption).foregroundStyle(Color.inkMuted)
                    AmountText(money: summary.bazarTotal, size: .bodyEmphasis)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Meals").font(AppFont.caption).foregroundStyle(Color.inkMuted)
                    MealNumberText(halfMeals: summary.totalHalfMeals).foregroundStyle(Color.ink)
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.lilac))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ summary: MessMonthSummary) -> some View {
        if summary.bazarExpenses.isEmpty {
            Text("Add bazar as an expense in the Bazar category. It shows here and can be split by meals.")
                .font(AppFont.caption)
                .foregroundStyle(Color.inkMuted)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button("Split bazar by meals") { confirmingSplit = true }
                    .buttonStyle(PillButtonStyle())
                    .disabled(summary.mealSplitRule == nil || isAlreadySplit(summary))
                Text(isAlreadySplit(summary)
                     ? LocalizedStringKey("This month's bazar is already shared by meals.")
                     : LocalizedStringKey("Rent and bills stay as you added them. Only bazar is shared by meals."))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
    }

    private func isAlreadySplit(_ summary: MessMonthSummary) -> Bool {
        guard let rule = summary.mealSplitRule else { return false }
        return summary.bazarExpenses.allSatisfy { $0.splitRule == rule }
    }

    private func load() async {
        do {
            summary = try await app.messSummary(for: group, month: month)
            errorMessage = nil
        } catch {
            summary = nil
            errorMessage = String(localized: "This month couldn't be worked out. Check the bazar expenses.", bundle: .appLanguage)
        }
    }

    private func applySplit() {
        guard let summary else { return }
        Task {
            do {
                try await app.applyMealSplit(summary, in: group)
                splitDone += 1
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "The bazar wasn't re-split. Try again.", bundle: .appLanguage)
            }
        }
    }
}

private struct MessMemberRow: View {
    let group: ExpenseGroup
    let member: Member
    let summary: MessMonthSummary

    var body: some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: member.displayName, size: 36)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: group.displayName(of: member.id))
                    .font(AppFont.body)
                    .foregroundStyle(Color.ink)
                HStack(spacing: Spacing.xxs) {
                    MealNumberText(halfMeals: summary.halfMeals[member.id] ?? 0, font: AppFont.caption)
                    Text("meals").font(AppFont.caption)
                }
                .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            AmountText(money: summary.mealCost[member.id] ?? .zero(summary.bazarTotal.currency), size: .bodyEmphasis)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
