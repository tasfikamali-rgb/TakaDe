import SwiftUI

/// Drag the thumb right to confirm (DESIGN.md section 4.5). Tracks 1:1, rubber-bands past
/// the end, springs back below 70% unless the flick's projected end crosses it. VoiceOver
/// users double-tap to confirm instead. `onConfirm` returns false if the action failed,
/// and the thumb springs back so the person can try again.
struct SwipeToConfirm: View {
    let title: String
    let onConfirm: () async -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var trackWidth: CGFloat = 0
    @State private var confirmed = false

    private let height: CGFloat = 64
    private let inset: CGFloat = 6
    private var thumb: CGFloat { height - inset * 2 }
    private var maxOffset: CGFloat { max(trackWidth - thumb - inset * 2, 1) }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.ink)
            Text(verbatim: title)
                .font(AppFont.bodyEmphasis)
                .foregroundStyle(Color.canvas.opacity(1 - Double(min(offset / maxOffset, 1)) * 0.8))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.leading, thumb + inset)
                .padding(.trailing, Spacing.m)
            Circle()
                .fill(Color.lime)
                .overlay(Image(systemName: confirmed ? "checkmark" : "arrow.right").font(.headline).foregroundStyle(Color.onLime))
                .frame(width: thumb, height: thumb)
                .padding(inset)
                .offset(x: offset)
                .gesture(drag)
        }
        .frame(minHeight: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trackWidth = $0 }
        .sensoryFeedback(.success, trigger: confirmed)
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
        Task {
            if await !onConfirm() {
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
