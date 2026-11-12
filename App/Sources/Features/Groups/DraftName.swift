import Foundation

/// A name in a form list, with a stable identity for `ForEach`.
struct DraftName: Identifiable, Hashable {
    let id = UUID()
    var text = ""
}
