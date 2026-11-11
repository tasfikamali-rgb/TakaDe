import SwiftUI

/// Overlapping avatars with a "+n" chip when there are more than `limit`.
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 28
    var limit = 4
    var ring: Color = .surface

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                Avatar(name: name, size: size, ring: ring)
            }
            if names.count > limit {
                Text(verbatim: "+\(names.count - limit)")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.surfaceRaised))
                    .overlay(Circle().stroke(ring, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
