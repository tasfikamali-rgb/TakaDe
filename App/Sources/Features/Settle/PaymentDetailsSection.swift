import SwiftUI
import TakaDeCore

struct PaymentDetailsSection: View {
    let isMePaying: Bool
    @Binding var method: SettlementMethod
    @Binding var reference: String

    var body: some View {
        Section {
            Picker("Paid with", selection: $method) {
                ForEach(SettlementMethod.allCases, id: \.self) { option in
                    Text(verbatim: option.label).tag(option)
                }
            }
            if method != .cash {
                TextField("Transaction ID (optional)", text: $reference)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        } footer: {
            if isMePaying {
                Text("Saved as recorded by you. It isn't checked with bKash, upay or any bank, and TakaDe never asks for your PIN.")
            } else {
                Text("Only mark it received once the money has reached you")
            }
        }
    }
}
