//
//  TorontoCouncillorCard.swift
//  epac
//
//  A tappable card linking to a Toronto councillor profile.
//

import SwiftUI
import UIKit

struct TorontoCouncillorCard: View {
    let councillor: TorontoCouncillor

    private var wardText: String {
        if let wardNumber = councillor.wardNumber {
            return String(format: NSLocalizedString("toronto.councillor.wardLabel", comment: ""), wardNumber, councillor.wardName)
        }
        return councillor.wardName
    }

    var body: some View {
        Link(destination: councillor.profileURL) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(UIColor.systemRed))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: NSLocalizedString("toronto.councillor.nameLabel", comment: ""), councillor.role, councillor.name))
                        .font(.subheadline.weight(.semibold))
                    Text(wardText)
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
        .accessibilityLabel("\(councillor.role) \(councillor.name), \(wardText), \(councillor.party), City of Toronto")
    }
}
