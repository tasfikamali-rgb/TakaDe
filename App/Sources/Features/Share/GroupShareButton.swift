import SwiftUI
import TakaDeCore

/// Shares "who pays whom" as an image plus text to WhatsApp, Messenger or anywhere.
/// Nothing else from the group (expense titles, notes, history) is included.
struct GroupShareButton: View {
    let group: ExpenseGroup
    let balances: GroupBalances

    @AppStorage(DigitPreference.storageKey) private var digitPreference: DigitPreference = .automatic
    @Environment(\.locale) private var locale
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?

    var body: some View {
        let summary = GroupSummary(group: group, balances: balances)
        let digits = digitPreference.resolved(for: locale)
        let text = ShareText.make(summary, digits: digits)
        Group {
            if let image {
                ShareLink(item: image, message: Text(verbatim: text), preview: SharePreview(Text(verbatim: group.name), image: image)) {
                    Label("Share balances", systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: text) {
                    Label("Share balances", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: text) { render(summary, digits: digits) }
    }

    private func render(_ summary: GroupSummary, digits: DigitStyle) {
        let renderer = ImageRenderer(content: GroupShareCard(summary: summary, digits: digits))
        renderer.scale = max(displayScale, 2)
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        }
    }
}
