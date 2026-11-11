import SwiftUI
import TakaDeCore

struct SplitSection: View {
    @Bindable var draft: ExpenseDraft

    var body: some View {
        Section {
            Picker("Split", selection: $draft.method) {
                ForEach(SplitMethod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            ForEach(draft.group.members) { member in
                SplitMemberRow(draft: draft, member: member)
            }
        } header: {
            Text("Split")
        } footer: {
            SplitFooter(draft: draft)
        }
    }
}
