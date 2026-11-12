import SwiftUI
import UIKit

/// A monochrome initial in a soft circle. The name itself is never altered; only its
/// first character is shown, which works for Bengali and Latin names alike. A person added
/// from Contacts shows their contact photo instead (see `MemberAvatar`).
struct Avatar: View {
    let name: String
    var size: CGFloat = 36
    var ring: Color = .surface
    var fill: Color = .surfaceRaised
    var photo: UIImage? = nil

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else if let initial {
                Text(verbatim: initial)
                    .font(AppFont.text(size * 0.42, .semibold, relativeTo: .body))
            } else {
                // No name yet: a person outline rather than a question mark.
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
            }
        }
        .foregroundStyle(Color.ink)
        .frame(width: size, height: size)
        .background(Circle().fill(fill))
        .clipShape(Circle())
        .overlay(Circle().stroke(ring, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private var initial: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
    }
}
