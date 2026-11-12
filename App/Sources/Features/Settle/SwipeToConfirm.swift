import SwiftUI

/// Drag the thumb right to confirm (DESIGN.md section 4.5). Tracks 1:1, rubber-bands past
/// the end, springs back below 70% unless the flick's projected end crosses it. VoiceOver
/// users double-tap to confirm instead. `onConfirm` returns false if the action failed,
/// and the thumb springs back so the person can try again.
struct SwipeToConfirm: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let onConfirm: () async -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var trackWidth: CGFloat = 0
    @State private var confirmed = false
    @State private var outcome: Bool?

    private let height: CGFloat = 64
    private let inset: CGFloat = 6
    private var thumb: CGFloat { height - inset * 2 }
    private var maxOffset: CGFloat { max(trackWidth - thumb - inset * 2, 1) }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.header)
                // Light mode has no dark surfaces, so the white track needs an edge and a lift.
                .overlay(Capsule().stroke(Color.ink.opacity(colorScheme == .dark ? 0 : 0.08), lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.14), radius: 16, y: 6)
            Text(verbatim: title)
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.onHeader.opacity(1 - Double(min(offset / maxOffset, 1)) * 0.8))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.leading, thumb + inset)
                .padding(.trailing, Spacing.m)
            Circle()
                .fill(Color.lime)
                .overlay(Circle().stroke(Color.ink.opacity(0.1), lineWidth: 1))
                .overlay(Image(systemName: confirmed ? "checkmark" : "arrow.right").font(.headline).foregroundStyle(Color.onLime))
                .frame(width: thumb, height: thumb)
                .padding(inset)
                .offset(x: offset)
                .gesture(drag)
        }
        .frame(minHeight: height)
        // Its own height only: in a bottom inset the capsule would otherwise take every
        // point it's offered and cover the sheet. Still grows for two lines of large text.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackWidth = $0 }
        .sensoryFeedback(trigger: outcome) { _, new in
            guard let new else { return nil }
            return new ? .success : .error
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Double-tap to confirm"))
        .accessibilityAction { commit() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !confirmed else { return }
                offset = Rubberband.clamp(value.translation.width, max: maxOffset)
            }
            .onEnded { value in
                guard !confirmed else { return }
                let projected = value.predictedEndTranslation.width
                if offset >= maxOffset * 0.7 || projected >= maxOffset * 1.1 {
                    commit()
                } else {
                    withAnimation(Motion.momentum(reduceMotion: reduceMotion)) { offset = 0 }
                }
            }
    }

    private func commit() {
        guard !confirmed else { return }
        withAnimation(Motion.standard(reduceMotion: reduceMotion)) {
            offset = maxOffset
            confirmed = true
        }
        outcome = nil
        Task {
            let succeeded = await onConfirm()
            outcome = succeeded
            if !succeeded {
                withAnimation(Motion.momentum(reduceMotion: reduceMotion)) {
                    offset = 0
                    confirmed = false
                }
            }
        }
    }
}

#Preview {
    SwipeToConfirm(title: "Swipe to record ৳ 450.00 paid", onConfirm: { true }).padding()
}
