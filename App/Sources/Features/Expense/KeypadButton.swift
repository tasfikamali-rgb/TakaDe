import SwiftUI

struct KeypadButton: View {
    enum Style { case digit, `operator` }

    let key: KeypadKey
    let style: Style
    let press: (KeypadKey) -> Void

    var body: some View {
        Button(action: tap) {
            Group {
                if key == .delete {
                    Image(systemName: "delete.left")
                } else {
                    Text(verbatim: key.label)
                }
            }
            .font(style == .digit ? AppFont.title : AppFont.headline)
            .frame(maxWidth: .infinity, minHeight: style == .digit ? 60 : 48)
            .background(
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .fill(style == .digit ? Color.surface : Color.surfaceRaised)
            )
            .foregroundStyle(Color.ink)
            .contentShape(RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(key.accessibilityLabel))
    }

    private func tap() { press(key) }
}
