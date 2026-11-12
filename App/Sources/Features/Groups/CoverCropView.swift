import SwiftUI
import UIKit

/// Move and zoom a new cover photo inside the 2:1 cover frame before it's saved (Sabit,
/// 2026-11-12: "there is no resizing option"). Drag to move, pinch to zoom; the photo always
/// fills the frame. VoiceOver users get Zoom in / Zoom out actions and can use it as is.
struct CoverCropView: View {
    let image: UIImage
    let onUse: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var saving = false
    @State private var failed = false
    @State private var frameSize: CGSize = .zero

    private static let maxZoom: CGFloat = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                GeometryReader { proxy in
                    let frame = CGSize(width: proxy.size.width, height: proxy.size.width / GroupPhotoFile.aspect)
                    let scale = clampedZoom(zoom * pinch)
                    let shown = shownSize(in: frame, zoom: scale)
                    let moved = clamp(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), shown: shown, frame: frame)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(moved)
                        .frame(width: frame.width, height: frame.height)
                        .clipped()
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Color.ink.opacity(0.25), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .updating($drag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    offset = clamp(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                                                   shown: shown, frame: frame)
                                }
                                .simultaneously(with: MagnifyGesture()
                                    .updating($pinch) { value, state, _ in state = value.magnification }
                                    .onEnded { value in
                                        zoom = clampedZoom(zoom * value.magnification)
                                        offset = clamp(offset, shown: shownSize(in: frame, zoom: zoom), frame: frame)
                                    })
                        )
                        .accessibilityElement()
                        .accessibilityLabel(Text("Cover photo"))
                        .accessibilityAddTraits(.isImage)
                        .accessibilityAction(named: Text("Zoom in")) { zoom = clampedZoom(zoom * 1.25) }
                        .accessibilityAction(named: Text("Zoom out")) {
                            zoom = clampedZoom(zoom / 1.25)
                            offset = clamp(offset, shown: shownSize(in: frame, zoom: zoom), frame: frame)
                        }
                        .onAppear { frameSize = frame }
                        .onChange(of: proxy.size) { _, _ in
                            frameSize = frame
                            offset = .zero
                        }
                }
                .aspectRatio(GroupPhotoFile.aspect, contentMode: .fit)
                Text("Drag to move the photo. Pinch to zoom.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
                if failed {
                    Text("That photo couldn't be used. Try another one.")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.owe)
                }
                Spacer()
            }
            .padding(Spacing.screenMargin)
            .readableWidth()
            .texturedBackground()
            .navigationTitle(Text("Cover photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") {
                        saving = true
                        Task { await save(frame: frameSize, zoom: zoom, offset: offset) }
                    }
                    .disabled(saving || frameSize == .zero)
                }
            }
        }
    }

    // MARK: Geometry

    /// The photo's size on screen: just big enough to fill the frame, times the zoom.
    private func shownSize(in frame: CGSize, zoom: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return frame }
        let fill = max(frame.width / image.size.width, frame.height / image.size.height) * zoom
        return CGSize(width: image.size.width * fill, height: image.size.height * fill)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat { min(max(value, 1), Self.maxZoom) }

    /// Keeps the photo covering the frame: no empty edge can show.
    private func clamp(_ offset: CGSize, shown: CGSize, frame: CGSize) -> CGSize {
        let maxX = max(0, (shown.width - frame.width) / 2)
        let maxY = max(0, (shown.height - frame.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// Renders exactly what's inside the frame, at up to `GroupPhotoFile.width` pixels wide,
    /// off the main thread.
    private func save(frame: CGSize, zoom: CGFloat, offset: CGSize) async {
        let shown = shownSize(in: frame, zoom: zoom)
        let image = self.image
        let data: Data? = await Task.detached(priority: .userInitiated) {
            guard frame.width > 0, frame.height > 0 else { return nil }
            // Output pixels per on-screen point: at most the cover width, never more than the
            // photo itself has, so it isn't blown up.
            let scale = max(0.1, min(GroupPhotoFile.width / frame.width, image.size.width * image.scale / shown.width))
            let output = CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let cropped = UIGraphicsImageRenderer(size: output, format: format).image { _ in
                let origin = CGPoint(x: (frame.width - shown.width) / 2 + offset.width, y: (frame.height - shown.height) / 2 + offset.height)
                image.draw(in: CGRect(x: origin.x * scale, y: origin.y * scale, width: shown.width * scale, height: shown.height * scale))
            }
            return cropped.jpegData(compressionQuality: 0.9)
        }.value
        if let data {
            onUse(data)
            dismiss()
        } else {
            failed = true
            saving = false
        }
    }
}
