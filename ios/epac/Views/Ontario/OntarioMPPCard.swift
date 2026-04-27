//
//  OntarioMPPCard.swift
//  epac
//
//  A tappable card linking to an Ontario MPP's OLA profile page.
//  Follows the same visual pattern as SenatorCard.
//

import SwiftUI
import UIKit

struct OntarioMPPCard: View {
    let mpp: OntarioMPP

    private var partyColor: Color {
        let p = mpp.party.lowercased()
        if p.contains("pc") || p.contains("conservative") { return Color(UIColor.systemBlue) }
        if p.contains("ndp") { return Color(UIColor.systemOrange) }
        if p.contains("liberal") { return Color(UIColor.systemRed) }
        if p.contains("green") { return Color(UIColor.systemGreen) }
        return Color(UIColor.systemGray)
    }

    var body: some View {
        Link(destination: mpp.profileURL) {
            HStack(spacing: 12) {
                Circle()
                    .fill(partyColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: NSLocalizedString("ontario.mpp.name", comment: ""), mpp.name))
                        .font(.subheadline.weight(.semibold))
                    Text(mpp.riding)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(mpp.party)
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
        .accessibilityLabel("\(mpp.name), MPP \(NSLocalizedString("ontario.mpp.for", comment: "")) \(mpp.riding), \(mpp.party)")
    }
}
