import PhotosUI
import SwiftUI
import TakaDeCore

/// "Scan receipt" with the camera where available, or pick a photo. The result is
/// shown for review before anything fills the form.
struct ReceiptScanButton: View {
    let onReviewed: (_ merchant: String?, _ total: Money?, _ date: Date?) -> Void
    /// The photo, kept with the expense so others can see what was paid.
    var onPhoto: ((CGImage) -> Void)? = nil

    @State private var showingCamera = false
    @State private var photo: PhotosPickerItem?
    @State private var suggestion: ReceiptSuggestion?
    @State private var image: CGImage?
    @State private var isReading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
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
            if let error {
                Text(verbatim: error).font(AppFont.caption).foregroundStyle(Color.owe)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScanner(onFinish: scanned, onCancel: closeCamera).ignoresSafeArea()
        }
        .sheet(item: $suggestion) { s in
            ReceiptReviewView(suggestion: s, image: image) { merchant, total, date in
                onReviewed(merchant, total, date)
                if let image { onPhoto?(image) }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
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
