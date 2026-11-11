import SwiftUI
import TakaDeCore

/// The image people send to their group chat. Shows only who pays whom.
/// Always rendered in light colors so it reads the same in any chat app.
struct GroupShareCard: View {
    let summary: GroupSummary
    let digits: DigitStyle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(verbatim: summary.groupName)
                .font(AppFont.title)
                .foregroundStyle(Color.ink)
            if summary.isSettled {
                Text("Everyone is settled up")
                    .font(AppFont.body)
                    .foregroundStyle(Color.inkMuted)
            } else {
                VStack(spacing: Spacing.s) {
                    ForEach(Array(summary.lines.enumerated()), id: \.offset) { _, line in
                        ShareCardLine(line: line, digits: digits)
                    }
                }
            }
            Rectangle()
                .fill(Color.ink.opacity(0.08))
                .frame(height: 1)
            Text(verbatim: "TakaDe")
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
        }
        .padding(Spacing.xl)
        .padding(.bottom, Spacing.xs)
        .frame(width: 360, alignment: .leading)
        .background(ReceiptEdge().fill(Color.surface))
        .padding(Spacing.xl)
        .background(Color.canvas)
        .environment(\.colorScheme, .light)
    }
}
