import SwiftUI
import TakaDeCore

/// What happened across all groups, as a feed of messages (Sabit, 2026-11-12): each change
/// anyone makes is one bubble, yours on the right and other people's on the left with their
/// picture, grouped by day, newest first. Changes that arrived since you last looked say
/// "New". Pull down to check shared groups now; the ৳ turns while it checks (Sabit,
/// 2026-11-12: no refresh button, pulling down is the refresh).
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @Environment(GroupSync.self) private var sync
    @Environment(ActivityInbox.self) private var inbox
    @Environment(\.locale) private var locale
    @State private var items: [ActivityItem] = []
    @State private var refresh = LogoRefreshState()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LogoRefreshHeader(state: refresh)
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    header
                    if items.isEmpty {
                        ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle",
                                               description: Text("Expenses, payments and edits in any group show up here"))
                            .padding(.top, Spacing.huge)
                    }
                    ForEach(days, id: \.start) { day in
                        dayTitle(day.start)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.m)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(day.items) { item in
                            ActivityBubble(item: item, isNew: newIDs.contains(item.id))
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xl)
            }
        }
        .logoRefreshable(state: refresh, action: checkNow)
        .texturedBackground()
        .readableWidth()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: TaskKey(revision: model.revision, locale: locale.identifier)) { await load() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Activity")
                .font(AppFont.title)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.top, Spacing.xs)
        .frame(minHeight: 44)
    }

    /// Pulls every shared group now. New changes reload the list through `model.revision`.
    private func checkNow() async {
        await sync.syncAll()
        await load()
    }

    private func load() async {
        items = await model.recentActivity(locale: locale)
    }

    /// The newest changes from other people that were unread when Activity opened.
    private var newIDs: Set<UUID> {
        Set(items.lazy.filter(\.isFromOthers).prefix(inbox.freshCount).map(\.id))
    }

    private struct Day {
        let start: Date
        let items: [ActivityItem]
    }

    /// Items are newest first already; this keeps that order within and across days.
    private var days: [Day] {
        let calendar = Calendar.current
        var result: [Day] = []
        for item in items {
            let start = calendar.startOfDay(for: item.occurredAt)
            if result.last?.start == start {
                result[result.count - 1] = Day(start: start, items: result[result.count - 1].items + [item])
            } else {
                result.append(Day(start: start, items: [item]))
            }
        }
        return result
    }

    private func dayTitle(_ date: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return Text("Today") }
        if calendar.isDateInYesterday(date) { return Text("Yesterday") }
        let sameYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        let style: Date.FormatStyle = sameYear ? .dateTime.weekday(.wide).day().month(.wide) : .dateTime.day().month(.wide).year()
        return Text(verbatim: date.formatted(style.locale(locale)))
    }

    private struct TaskKey: Hashable {
        let revision: Int
        let locale: String
    }
}

/// One change as a message. Other people's sit on the left beside their picture; yours sit
/// on the right. The flat corner points at whoever made it.
struct ActivityBubble: View {
    let item: ActivityItem
    var isNew = false

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            if item.isMine {
                Spacer(minLength: Spacing.huge)
            } else {
                avatar
            }
            bubble
            if !item.isMine {
                Spacer(minLength: Spacing.xl)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var avatar: some View {
        if let actor = item.actor, let member = item.group.member(actor) {
            MemberAvatar(member: member, size: 32)
        } else {
            GroupIconBadge(name: item.group.name, size: 32, fill: .surfaceRaised)
        }
    }

    private var shape: UnevenRoundedRectangle {
        let round: CGFloat = 18, flat: CGFloat = 6
        return UnevenRoundedRectangle(topLeadingRadius: round,
                                      bottomLeadingRadius: item.isMine ? round : flat,
                                      bottomTrailingRadius: item.isMine ? flat : round,
                                      topTrailingRadius: round,
                                      style: .continuous)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(verbatim: item.headline)
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let amount = item.amount {
                    Spacer(minLength: 0)
                    AmountText(money: amount, size: .headline, color: item.isRemoved ? .inkMuted : .ink)
                        .strikethrough(item.isRemoved)
                        .layoutPriority(1)
                }
            }
            ForEach(item.details, id: \.self) { line in
                Text(verbatim: line)
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink)
            }
            HStack(spacing: Spacing.xxs) {
                if isNew {
                    Circle().fill(Color.lime).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("New").foregroundStyle(Color.lime)
                    Text(verbatim: "·")
                }
                Text(verbatim: item.group.name).lineLimit(1)
                Text(verbatim: "·")
                Text(item.occurredAt, format: .dateTime.hour().minute())
            }
            .font(AppFont.caption)
            .foregroundStyle(Color.inkMuted)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(shape.fill(item.isMine ? Color.surfaceRaised : Color.surface))
        .overlay {
            if isNew { shape.strokeBorder(Color.lime.opacity(0.55), lineWidth: 1) }
        }
    }
}
