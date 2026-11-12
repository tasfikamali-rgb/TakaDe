import SwiftUI
import TakaDeCore

/// The receipt on an expense, so everyone in the group can see what was paid. The phone
/// that took the photo shows the photo; the others in a shared group get the text read from
/// it (ADR 28), fetched from the relay the first time. Tap to see it full size.
///
/// The full-size view is presented by the screen that owns the form (`onOpen`), not from
/// here: a presentation modifier on a `Section` is copied onto every row of a `Form`, so the
/// two rows each tried to show the same cover and the second closed the first. Rows are
/// also rebuilt when a shared group syncs every 20 seconds, which closed it again.
struct ReceiptPhotoSection: View {
    @Environment(GroupSync.self) private var sync
    let draft: ExpenseDraft
    let onOpen: (OpenReceipt) -> Void

    @State private var content: GroupSync.ReceiptContent?
    @State private var loading = false

    var body: some View {
        Section {
            Button { if let content { onOpen(OpenReceipt(content: content)) } } label: {
                HStack(spacing: Spacing.m) {
                    Group {
                        switch content {
                        case .photo(let image):
                            Image(decorative: image, scale: 1).resizable().scaledToFill()
                        case .text:
                            Image(systemName: "doc.plaintext").foregroundStyle(Color.ink)
                        case nil:
                            if loading { ProgressView() } else { Image(systemName: "doc.text.image").foregroundStyle(Color.inkMuted) }
                        }
                    }
                    .frame(width: 56, height: 72)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
                    Text(label).foregroundStyle(Color.ink)
                }
            }
            .accessibilityHint(content != nil ? Text("Shows the receipt full size") : Text(verbatim: ""))
            // On the row, not the Section, so it runs once and not once per row.
            .task(id: draft.receiptID) { await load() }
            .onChange(of: draft.newReceipt == nil) { Task { await load() } }
            Button(role: .destructive) { draft.removeReceipt() } label: {
                Text(isText ? LocalizedStringKey("Remove receipt") : LocalizedStringKey("Remove photo"))
            }
        } footer: {
            if isText {
                Text("The photo is on the phone of the person who added this receipt. You see the text read from it, encrypted on the way here.")
            } else {
                Text("In a shared group, the others see the text read from this receipt, not the photo. The photo stays on this phone. The text is encrypted before it's sent.")
            }
        }
    }

    private var isText: Bool {
        if case .text = content { return true }
        return false
    }

    private var label: LocalizedStringKey {
        switch content {
        case .photo: "Receipt photo"
        case .text: "Receipt text"
        case nil: loading ? "Receipt photo" : "The receipt isn't on this phone yet. Check your connection."
        }
    }

    private func load() async {
        if let fresh = draft.newReceipt {
            content = .photo(fresh)
            return
        }
        guard let id = draft.receiptID else { content = nil; return }
        loading = true
        let fetched = await sync.receipt(id, in: draft.group.id)
        // Keep what's shown if a later load comes back empty (offline for a moment).
        if fetched != nil || content == nil { content = fetched }
        loading = false
    }
}

/// The receipt opened full size. A snapshot, so a reload behind it can't change or close it.
struct OpenReceipt: Identifiable {
    let id = UUID()
    let content: GroupSync.ReceiptContent
}

/// Shows an opened receipt: the photo, or the text when the photo is on someone else's phone.
struct ReceiptViewer: View {
    let receipt: OpenReceipt

    var body: some View {
        switch receipt.content {
        case .photo(let image): ReceiptPhotoViewer(image: image)
        case .text(let lines): ReceiptTextViewer(lines: lines)
        }
    }
}

/// The receipt's text exactly as it was read: English, as printed, never translated.
struct ReceiptTextViewer: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label {
                        Text("The photo stays on the phone of the person who added it. This is the text read from it.")
                    } icon: {
                        Image(systemName: "iphone").accessibilityHidden(true)
                    }
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
                    .padding(.bottom, Spacing.s)
                    if lines.isEmpty {
                        Text("No text could be read from this receipt.")
                            .font(AppFont.body)
                            .foregroundStyle(Color.inkMuted)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
                .padding(Spacing.l)
                .readableWidth()
            }
            .background(Color.canvas)
            .navigationTitle(Text("Receipt text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Full screen, pinch to zoom.
struct ReceiptPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: CGImage
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .containerRelativeFrame(.horizontal) { width, _ in width * scale }
                    .accessibilityLabel(Text("Receipt photo"))
            }
            .gesture(MagnifyGesture().onChanged { scale = min(4, max(1, $0.magnification)) })
            .background(Color.canvas)
            .navigationTitle(Text("Receipt photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
