import Observation

/// App-wide chrome state that screens deep in a navigation stack can change.
@MainActor
@Observable
final class AppChrome {
    /// True while a pushed screen (a group) owns the bottom edge for its own actions,
    /// so the notch bar steps aside instead of covering "Settle up".
    var hidesTabBar = false
}
