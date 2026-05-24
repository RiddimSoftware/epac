//
//  ElectionResourcesView.swift
//  epac
//

import SwiftUI

private enum Layout {
    static let rowSpacing: CGFloat = 12
    static let iconWidth: CGFloat = 28
}

struct ElectionResourcesView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section(NSLocalizedString("election.register.header", comment: "")) {
                resourceRow(
                    title: NSLocalizedString("election.register.check", comment: ""),
                    subtitle: NSLocalizedString("election.register.check.subtitle", comment: ""),
                    icon: "checkmark.circle.fill",
                    color: .green,
                    url: "https://ereg.elections.ca/CWelcome.aspx"
                )
                resourceRow(
                    title: NSLocalizedString("election.register.polling", comment: ""),
                    subtitle: NSLocalizedString("election.register.polling.subtitle", comment: ""),
                    icon: "mappin.and.ellipse",
                    color: .red,
                    url: "https://www.elections.ca/content.aspx?section=vot&dir=bkg&document=ec90515&lang=e"
                )
                resourceRow(
                    title: NSLocalizedString("election.register.id", comment: ""),
                    subtitle: NSLocalizedString("election.register.id.subtitle", comment: ""),
                    icon: "person.text.rectangle.fill",
                    color: .blue,
                    url: "https://www.elections.ca/content.aspx?section=vot&dir=ids&document=index&lang=e"
                )
            }

            Section(NSLocalizedString("election.research.header", comment: "")) {
                resourceRow(
                    title: NSLocalizedString("election.research.candidates", comment: ""),
                    subtitle: NSLocalizedString("election.research.candidates.subtitle", comment: ""),
                    icon: "person.3.fill",
                    color: .purple,
                    url: "https://www.elections.ca/content.aspx?section=ele&document=index&dir=pas&lang=e"
                )
                resourceRow(
                    title: NSLocalizedString("election.research.results", comment: ""),
                    subtitle: NSLocalizedString("election.research.results.subtitle", comment: ""),
                    icon: "chart.bar.fill",
                    color: .orange,
                    url: "https://www.elections.ca/content.aspx?section=res&dir=rep&document=index&lang=e"
                )
                resourceRow(
                    title: NSLocalizedString("election.research.financing", comment: ""),
                    subtitle: NSLocalizedString("election.research.financing.subtitle", comment: ""),
                    icon: "dollarsign.circle.fill",
                    color: .teal,
                    url: "https://www.elections.ca/content.aspx?section=fin&document=index&lang=e"
                )
            }

            Section {
                Text(NSLocalizedString("election.disclaimer", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("election.navTitle", comment: ""))
        .navigationBarTitleDisplayMode(.large)
    }

    private func resourceRow(title: String, subtitle: String, icon: String, color: Color, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: Layout.rowSpacing) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: Layout.iconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                    Text(title).font(.subheadline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
