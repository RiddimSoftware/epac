import SwiftUI

struct FederalContractDetailView: View {
    let contract: GovernmentContract

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: EpacSpacing.s) {
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
                .padding(.vertical, EpacSpacing.xs)
            }

            Section(NSLocalizedString("contracts.detail.info", comment: "")) {
                LabeledContent(NSLocalizedString("contracts.detail.date", comment: ""),
                               value: contract.contractDate.formatted(date: .long, time: .omitted))
                if let end = contract.endDate {
                    LabeledContent(NSLocalizedString("contracts.detail.endDate", comment: ""),
                                   value: end.formatted(date: .long, time: .omitted))
                }
                if !contract.fiscalYear.isEmpty {
                    LabeledContent(NSLocalizedString("contracts.detail.fiscal", comment: ""),
                                   value: contract.fiscalYear)
                }
                if !contract.contractType.isEmpty {
                    LabeledContent(NSLocalizedString("contracts.detail.contractType", comment: ""),
                                   value: contract.contractType)
                }
                if contract.originalValue != contract.value {
                    LabeledContent(NSLocalizedString("contracts.detail.original", comment: ""),
                                   value: contract.formattedOriginalValue)
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
                DataSourceBadge(source: .proactiveContracts())
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("contracts.detail.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
