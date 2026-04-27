//
//  VancouverCouncillorCard.swift
//  epac
//
//  A tappable card linking to a Vancouver city councillor's profile.
//  Follows the same visual pattern as OntarioMPPCard.
//

import SwiftUI
import UIKit

struct VancouverCouncillorCard: View {
    let councillor: VancouverCouncillor

    private var partyColor: Color {
        switch councillor.party.uppercased() {
        case "ABC":   return Color(UIColor.systemBlue)
        case "GREEN": return Color(UIColor.systemGreen)
        default:      return Color(UIColor.systemGray)
        }
    }

    var body: some View {
        Link(destination: councillor.profileURL) {
            HStack(spacing: 12) {
                Circle()
                    .fill(partyColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: NSLocalizedString("vancouver.councillor.nameLabel", comment: ""), councillor.role, councillor.name))
                        .font(.subheadline.weight(.semibold))
                    Text(councillor.party)
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
        .accessibilityLabel("\(councillor.role) \(councillor.name), \(councillor.party), City of Vancouver")
    }
}
