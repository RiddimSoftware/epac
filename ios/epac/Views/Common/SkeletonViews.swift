//
//  SkeletonViews.swift
//  epac
//
//  Placeholder row views used during skeleton loading states.
//

import SwiftUI

/// Placeholder MP row matching MemberRow dimensions.
struct MemberRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 14)
                    .frame(maxWidth: 180)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(height: 10)
                    .frame(maxWidth: 120)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Placeholder bill row matching BillRow dimensions.
struct BillRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 12)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 70, height: 18)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray6))
                .frame(height: 14)
                .frame(maxWidth: 200)
        }
        .padding(.vertical, 4)
    }
}
