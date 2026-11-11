import SwiftUI
import UIKit
import TakaDeCore

/// "bKash  01712-345678  [Copy]". Copying is the whole job: TakaDe doesn't open the
/// wallet app or move money.
struct PaymentHandleRow: View {
    let handle: PaymentHandle
    @State private var copied = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: handle.rail.label)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
                Text(verbatim: handle.displayHandle)
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            Spacer()
            Button(action: copy) {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(AppFont.label)
            }
            .buttonStyle(.bordered)
            .tint(Color.ink)
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Copy")) { copy() }
    }

    private func copy() {
        UIPasteboard.general.string = handle.handle
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
