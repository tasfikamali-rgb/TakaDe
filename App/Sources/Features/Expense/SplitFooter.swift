import SwiftUI
import TakaDeCore

/// Neutral while the person is still typing; red only for real mistakes.
struct SplitFooter: View {
    let draft: ExpenseDraft

    var body: some View {
        switch draft.preview {
        case .some(.failure(.exactAmountsDoNotMatchTotal(let expected, let actual))) where actual < expected:
            Text(verbatim: SplitErrorMessage.leftToAssign(expected: expected, actual: actual))
                .foregroundStyle(Color.inkMuted)
        case .some(.failure(let error)):
            Text(verbatim: SplitErrorMessage.text(for: error)).foregroundStyle(Color.owe)
        case .some(.success), .none:
            if draft.showsOldSplitAsAmounts, draft.method == .exact {
                Text("This was split by percent or with extras. It now shows each person's amount, so nothing changes unless you edit it.")
            } else if draft.hasRoundingRemainder {
                Text("Leftover poisha go to the first people listed, so the total always matches")
            }
        }
    }
}
