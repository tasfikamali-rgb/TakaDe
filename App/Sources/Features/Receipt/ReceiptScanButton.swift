import PhotosUI
import SwiftUI
import TakaDeCore

/// "Scan receipt" with the camera where available, or pick a photo. The result is
/// shown for review before anything fills the form.
///
/// With `onEnterAmount`, it shows three large, equal choices instead (Scan receipt,
/// From photos, Enter amount), for a new expense that has no amount yet: Add expense
/// opens on these rather than jumping to the number pad (Sabit, 2026-11-12).
struct ReceiptScanButton: View {
    let onReviewed: (_ merchant: String?, _ total: Money?, _ date: Date?) -> Void
    var onEnterAmount: (() -> Void)?

    @State private var showingCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var suggestion: ReceiptSuggestion?
    @State private var image: CGImage?
    @State private var isReading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let onEnterAmount {
                choices(onEnterAmount)
            } else {
                HStack(spacing: Spacing.m) {
                    if DocumentScanner.isAvailable {
                        Button("Scan receipt", systemImage: "doc.viewfinder", action: openCamera)
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(DocumentScanner.isAvailable ? "From photos" : "Scan receipt from photos", systemImage: "photo")
                    }
                    if isReading { ProgressView() }
                }
                .buttonStyle(.borderless)
            }
            if let error {
                Text(verbatim: error).font(AppFont.caption).foregroundStyle(Color.owe)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScanner(onFinish: scanned, onCancel: closeCamera).ignoresSafeArea()
        }
        .sheet(item: $suggestion) { s in
            ReceiptReviewView(suggestion: s, image: image, onUse: onReviewed)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
    }

    /// Side by side when they fit, stacked at large text sizes.
    private func choices(_ onEnterAmount: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) { choiceTiles(onEnterAmount) }
            VStack(spacing: Spacing.s) { choiceTiles(onEnterAmount) }
        }
        .overlay {
            if isReading {
                ProgressView()
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            }
        }
    }

    @ViewBuilder
    private func choiceTiles(_ onEnterAmount: @escaping () -> Void) -> some View {
        if DocumentScanner.isAvailable {
            Button(action: openCamera) { ChoiceTile(title: "Scan receipt", systemImage: "doc.viewfinder") }
                .buttonStyle(.plain)
        }
        PhotosPicker(selection: $photo, matching: .images) {
            ChoiceTile(title: "From photos", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.plain)
        Button(action: onEnterAmount) { ChoiceTile(title: "Enter amount", systemImage: "number") }
            .buttonStyle(.plain)
    }

    private func openCamera() { showingCamera = true }
    private func closeCamera() { showingCamera = false }

    private func scanned(_ images: [CGImage]) {
        showingCamera = false
        Task { await recognize(images) }
    }

    private func read(_ item: PhotosPickerItem) async {
        defer { photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage else {
            error = String(localized: "That photo couldn't be opened. Try another one.", bundle: .appLanguage)
            return
        }
        await recognize([image])
    }

    private func recognize(_ images: [CGImage]) async {
        isReading = true
        defer { isReading = false }
        do {
            let lines = try await ReceiptTextRecognizer.lines(in: images)
            let result = ReceiptParser.parse(lines: lines)
            image = images.first
            if result.total == nil {
                error = String(localized: "No amount found. Try a sharper, flatter photo, or type it in.", bundle: .appLanguage)
            } else {
                error = nil
                suggestion = result
            }
        } catch {
            self.error = String(localized: "The receipt couldn't be read. Type the amount instead.", bundle: .appLanguage)
        }
    }
}

/// One of the big starting choices in Add expense.
private struct ChoiceTile: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .accessibilityHidden(true)
            Text(title)
                .font(AppFont.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(.horizontal, Spacing.xs)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
