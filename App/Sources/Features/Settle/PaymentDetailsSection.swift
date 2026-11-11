import SwiftUI
import TakaDeCore

struct PaymentDetailsSection: View {
    let isMePaying: Bool
    @Binding var method: SettlementMethod
    @Binding var reference: String
    var duplicateWarning: String?

    private var isWallet: Bool { [.bkash, .nagad, .rocket, .upay].contains(method) }

    var body: some View {
        Section {
            Picker("Paid with", selection: $method) {
                ForEach(SettlementMethod.allCases, id: \.self) { option in
                    Text(verbatim: option.label).tag(option)
                }
            }
            if method != .cash {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Group {
                        if isWallet {
                            Text("\(method.label) TrxID")
                        } else {
                            Text("Transaction ID")
                        }
                    }
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
                    TextField("Optional, like 8N7A6B5C4D", text: $reference)
                        .font(AppFont.bodyEmphasis)
                        .monospaced()
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, Spacing.xxs)
                if let duplicateWarning {
                    Label {
                        Text(verbatim: duplicateWarning)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(AppFont.label)
                    .foregroundStyle(Color.owe)
                }
            }
        } footer: {
            if isMePaying, isWallet {
                Text("The TrxID is in the \(method.label) message after you pay. It's saved as typed by you and isn't checked with \(method.label). TakaDe never asks for your PIN.")
            } else if isMePaying {
                Text("Saved as recorded by you. It isn't checked with bKash, upay or any bank, and TakaDe never asks for your PIN.")
            } else {
                Text("Only mark it received once the money has reached you")
            }
        }
    }
}
