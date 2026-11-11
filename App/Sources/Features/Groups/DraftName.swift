import Foundation

/// A name being typed into a form row, with a stable identity for `ForEach`.
struct DraftName: Identifiable, Hashable {
    let id = UUID()
    var text = ""
}
