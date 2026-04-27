import SwiftUI

struct FederalContractDetailView: View {
    let contract: GovernmentContract

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(contract.formattedValue)
                            .font(.title2.bold())
                            .foregroundStyle(contract.isHighValue ? .orange : .primary)
                        if contract.amendmentCount > 0 {
                            Spacer()
                            Text(String(format: NSLocalizedString("contracts.detail.amendments", comment: ""), contract.amendmentCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(contract.vendor)
                        .font(.headline)
                    Text(contract.department)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(NSLocalizedString("contracts.detail.info", comment: "")) {
                LabeledContent(NSLocalizedString("contracts.detail.date", comment: ""),
                               value: contract.contractDate.formatted(date: .long, time: .omitted))
                if !contract.fiscalYear.isEmpty {
                    LabeledContent(NSLocalizedString("contracts.detail.fiscal", comment: ""),
                                   value: contract.fiscalYear)
                }
                if contract.originalValue != contract.value {
                    LabeledContent(NSLocalizedString("contracts.detail.original", comment: ""),
                                   value: contract.formattedValue)
                }
                LabeledContent(NSLocalizedString("contracts.detail.refNumber", comment: ""),
                               value: contract.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !contract.purpose.isEmpty {
                Section(NSLocalizedString("contracts.detail.purpose", comment: "")) {
                    Text(contract.purpose)
                        .font(.body)
                }
            }

            Section(NSLocalizedString("contracts.detail.source", comment: "")) {
                Link(destination: GovernmentContract.datasetURL) {
                    Label {
                        Text(NSLocalizedString("contracts.detail.openData", comment: ""))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "link")
                    }
                }
                LabeledContent(
                    NSLocalizedString("contracts.detail.sourceLabel", comment: ""),
                    value: NSLocalizedString("contracts.detail.sourceName", comment: "")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("contracts.detail.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
