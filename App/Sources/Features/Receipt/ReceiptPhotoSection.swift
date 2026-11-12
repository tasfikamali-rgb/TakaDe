import SwiftUI
import TakaDeCore

/// The receipt photo on an expense, so everyone in the group can see what was paid.
/// Tap to see it full size. In a shared group it's fetched from the relay the first time.
struct ReceiptPhotoSection: View {
    @Environment(GroupSync.self) private var sync
    let draft: ExpenseDraft

    @State private var image: CGImage?
    @State private var loading = false
    @State private var showingFull = false

    var body: some View {
        Section {
            Button { if image != nil { showingFull = true } } label: {
                HStack(spacing: Spacing.m) {
                    Group {
                        if let image {
                            Image(decorative: image, scale: 1).resizable().scaledToFill()
                        } else if loading {
                            ProgressView()
                        } else {
                            Image(systemName: "doc.text.image").foregroundStyle(Color.inkMuted)
                        }
                    }
                    .frame(width: 56, height: 72)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
                    Text(image == nil && !loading
                         ? LocalizedStringKey("The photo isn't on this phone yet. Check your connection.")
                         : LocalizedStringKey("Receipt photo"))
                        .foregroundStyle(Color.ink)
                }
            }
            .accessibilityHint(image != nil ? Text("Shows the photo full size") : Text(verbatim: ""))
            Button("Remove photo", role: .destructive) { draft.removeReceipt() }
        } footer: {
            Text("In a shared group, everyone in it can see this photo. It's encrypted on the phone before it's sent.")
        }
        .task(id: draft.receiptID) { await load() }
        .onChange(of: draft.newReceipt == nil) { Task { await load() } }
        .fullScreenCover(isPresented: $showingFull) {
            if let image { ReceiptPhotoViewer(image: image) }
        }
    }

    private func load() async {
        if let fresh = draft.newReceipt {
            image = fresh
            return
        }
        guard let id = draft.receiptID else { image = nil; return }
        loading = true
        image = await sync.receiptImage(id, in: draft.group.id)
        loading = false
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
