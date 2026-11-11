import SwiftUI
import TakaDeCore

struct KeypadButton: View {
    enum Style { case digit, `operator` }

    @AppStorage(DigitPreference.storageKey) private var digitPreference: DigitPreference = .automatic
    @Environment(\.locale) private var locale

    let key: KeypadKey
    let style: Style
    let press: (KeypadKey) -> Void

    var body: some View {
        Button(action: tap) {
            let bengali = digitPreference.resolved(for: locale) == .bengali
            Group {
                if key == .delete {
                    Image(systemName: "delete.left")
                } else {
                    Text(verbatim: bengali ? Digits.toBengali(key.label) : key.label)
                }
            }
            .font(style == .digit ? AppFont.display(28, relativeTo: .title, bengali: bengali) : AppFont.headline)
            .frame(maxWidth: .infinity, minHeight: style == .digit ? 60 : 48)
            .background(
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .fill(style == .digit ? Color.surface : Color.surfaceRaised)
            )
            .foregroundStyle(Color.ink)
            .contentShape(RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in clearIfDelete() })
        .accessibilityLabel(Text(key.accessibilityLabel))
        .accessibilityHint(key == .delete ? Text("Hold to clear") : Text(verbatim: ""))
    }

    private func clearIfDelete() {
        if key == .delete { press(.clear) }
    }

    private func tap() { press(key) }
}
