import SwiftUI
import TakaDeCore

struct SplitFooter: View {
    let draft: ExpenseDraft

    var body: some View {
        switch draft.preview {
        case .some(.failure(let error)):
            Text(verbatim: SplitErrorMessage.text(for: error)).foregroundStyle(Color.owe)
        case .some(.success), .none:
            if draft.method == .equal {
                Text("Leftover poisha go to the first people listed, so the total always matches")
            }
        }
    }
}
