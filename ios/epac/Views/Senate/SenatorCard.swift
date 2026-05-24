//
//  SenatorCard.swift
//  epac
//
//  Created on 2026-04-27.
//
//  A tappable card linking to a senator's Senate of Canada profile page.
//

import SwiftUI

private enum Layout {
    static let rowSpacing: CGFloat = 12
    static let caucusDotSize: CGFloat = 10
}

struct SenatorCard: View {
    let senator: Senator

    var body: some View {
        Link(destination: senator.senateURL) {
            HStack(spacing: Layout.rowSpacing) {
                Circle()
                    .fill(senator.caucusColor)
                    .frame(width: Layout.caucusDotSize, height: Layout.caucusDotSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EpacSpacing.xxs) {
                    Text(String(format: NSLocalizedString("senate.card.name", comment: ""), senator.name))
                        .font(.subheadline.weight(.semibold))
                    Text(senator.caucusFullName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, EpacSpacing.xxs)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(
            String(format: NSLocalizedString("senate.card.accessibility", comment: ""),
                   senator.name, senator.caucusFullName)
        )
    }
}
