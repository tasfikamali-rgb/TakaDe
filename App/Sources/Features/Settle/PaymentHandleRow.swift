import SwiftUI
import UIKit
import TakaDeCore

/// "bKash  01712-345678  [Copy]". Copying is the whole job: TakaDe doesn't move money.
struct PaymentHandleRow: View {
    let handle: PaymentHandle

    var body: some View {
        CopyRow(title: handle.rail.label, display: handle.displayHandle, value: handle.handle)
    }
}

/// A small label, a value in bold and a Copy button that briefly turns into "Copied".
struct CopyRow: View {
    let title: String
    let display: String
    /// What goes on the clipboard: Latin digits, so it pastes cleanly into wallet apps.
    let value: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
                Text(verbatim: display)
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
        UIPasteboard.general.string = value
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
