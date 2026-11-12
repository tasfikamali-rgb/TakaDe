import SwiftUI

/// Springs from DESIGN.md section 7 and the apple-design skill.
/// Critically damped by default; bounce only after a gesture carried momentum.
enum Motion {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
    static let momentum = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let sheet = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// The tab bar's sliding pill: quick, with a small settle at the end.
    static let tabSwitch = Animation.spring(response: 0.34, dampingFraction: 0.76)
    static let press = Animation.easeOut(duration: 0.1)
    /// What to use instead of slides and springs when Reduce Motion is on.
    static let reduced = Animation.easeInOut(duration: 0.2)

    static func standard(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : standard }
    static func momentum(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : momentum }
    static func tabSwitch(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : tabSwitch }
}
