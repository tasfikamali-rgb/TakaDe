import SwiftUI

/// The two-layer screen from DESIGN.md 1b for forms: a tinted header holding the one big
/// number, and a canvas sheet with rounded top corners holding the fields. The header
/// stays put while the fields scroll, so the amount is always in view. In short windows
/// (landscape phones) the header gets less padding so the fields keep their room.
struct LayeredForm<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, isShort ? Spacing.xxs : Spacing.s)
                .padding(.bottom, (isShort ? Spacing.s : Spacing.xl) + Radius.sheet)
                .readableWidth()
                .background(TexturedBackground(base: .lilac))
            Form {
                Group { content }
                    .listRowBackground(Color.surface)
            }
                .scrollContentBackground(.hidden)
                .background(TexturedBackground())
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous))
                .padding(.top, -Radius.sheet)
                .readableWidth()
        }
        // Lilac behind the navigation bar and the header, canvas behind everything below.
        .background {
            VStack(spacing: 0) {
                Color.lilac
                Color.canvas
            }
            .ignoresSafeArea()
        }
        .toolbarBackground(Color.lilac, for: .navigationBar)
    }

    private var isShort: Bool { verticalSizeClass == .compact }
}
