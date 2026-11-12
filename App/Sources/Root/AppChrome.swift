import Observation

/// App-wide chrome state that screens deep in a navigation stack can change.
@MainActor
@Observable
final class AppChrome {
    /// True while a pushed screen (a group) owns the bottom edge for its own actions,
    /// so the pill bar steps aside instead of covering "Settle up".
    var hidesTabBar = false
    /// Whether this window uses the floating pill bar (set by RootView from the window shape).
    var showsPillBar = true
    /// The New group and Join a group sheets. They're shown from RootView, above the tabs,
    /// because the tabs are rebuilt on a text size or language change, and a sheet shown
    /// from inside them closed when that happened (the accessibility audit changes the
    /// text size, so it closed the sheet mid-audit).
    var showsNewGroup = false
    var showsJoin = false
}
