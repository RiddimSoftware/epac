//
//  SenatorCard.swift
//  epac
//
//  Created on 2026-04-27.
//
//  A tappable card linking to a senator's Senate of Canada profile page.
//

import SwiftUI

struct SenatorCard: View {
    let senator: Senator

    var body: some View {
        Link(destination: senator.senateURL) {
            HStack(spacing: 12) {
                Circle()
                    .fill(senator.caucusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 2)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(
            String(format: NSLocalizedString("senate.card.accessibility", comment: ""),
                   senator.name, senator.caucusFullName)
        )
    }
}
