import SwiftUI

extension View {
    /// For a `TextField` with `axis: .vertical`, which wraps long text at large sizes but
    /// would otherwise turn Return into a new line. Removes line breaks as they're typed or
    /// pasted, and runs `action` (usually moving to the next field) when Return is pressed.
    func returnMovesOn(_ text: Binding<String>, perform action: @escaping () -> Void) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            guard new.contains(where: \.isNewline) else { return }
            text.wrappedValue = new.filter { !$0.isNewline }
            action()
        }
    }
}
