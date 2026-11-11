import SwiftUI

/// A titled white card used for each block on the group sheet.
struct SectionCard<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.ink)
                Spacer()
                trailing
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
        }
    }
}

extension SectionCard where Trailing == EmptyView {
    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }
}
