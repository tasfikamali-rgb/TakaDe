import SwiftUI
import TakaDeCore

struct ShareCardLine: View {
    let line: GroupSummary.Line
    let digits: DigitStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(line.from) pays \(line.to)")
                .font(AppFont.body)
                .foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.s)
            Text(verbatim: MoneyFormatter.format(line.amount, digits: digits).plain)
                .font(AppFont.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
    }
}
