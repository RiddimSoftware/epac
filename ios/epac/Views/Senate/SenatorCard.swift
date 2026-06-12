//
//  SenatorCard.swift
//  epac
//
//  Created on 2026-04-27.
//
//  A tappable card linking to a senator's Senate of Canada profile page.
//

import SwiftUI
import UIKit

private enum Layout {
    static let rowSpacing: CGFloat = 12
    static let caucusDotSize: CGFloat = 10
}

struct SenatorCard: View {
    let senator: Senator

    var body: some View {
        HStack(alignment: .top, spacing: Layout.rowSpacing) {
            Circle()
                .fill(caucusColor)
                .frame(width: Layout.caucusDotSize, height: Layout.caucusDotSize)
                .padding(.top, EpacSpacing.xxs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                Text(String(format: NSLocalizedString("senate.card.name", comment: ""), senator.name))
                    .font(.subheadline.weight(.semibold))
                Text(senator.caucusFullName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let appointmentSummary {
                    Text(appointmentSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: senator.appointmentSourceURL) {
                        Label(NSLocalizedString("senate.card.source", comment: ""), systemImage: "doc.text")
                            .font(.caption2)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Link(destination: senator.senateURL) {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .accessibilityLabel(String(format: NSLocalizedString("senate.card.name", comment: ""), senator.name))
        }
        .padding(.vertical, EpacSpacing.xxs)
        .foregroundStyle(.primary)
        .accessibilityLabel(
            String(format: NSLocalizedString("senate.card.accessibility", comment: ""),
                   senator.name, senator.caucusFullName, appointmentSummary ?? "")
        )
    }

    private var appointmentSummary: String? {
        guard let date = senator.appointmentDate else { return nil }
        let formattedDate = Self.appointmentDateFormatter.string(from: date)
        if let primeMinister = senator.appointment?.appointingPrimeMinister, !primeMinister.isEmpty {
            return String(
                format: NSLocalizedString("senate.card.appointed", comment: ""),
                primeMinister,
                formattedDate
            )
        }
        return String(format: NSLocalizedString("senate.card.appointedUnknownPM", comment: ""), formattedDate)
    }

    private var caucusColor: Color {
        switch senator.caucus.uppercased() {
        case "CPC", "CONS": return Color(UIColor.systemBlue)
        case "PSG":         return Color(UIColor.systemRed)
        case "ISG":         return Color(UIColor.systemTeal)
        case "CSG":         return Color(UIColor.systemPurple)
        default:            return Color(UIColor.systemGray)
        }
    }

    private static let appointmentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
