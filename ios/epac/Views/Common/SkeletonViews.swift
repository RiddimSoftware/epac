//
//  SkeletonViews.swift
//  epac
//
//  Placeholder row views used during skeleton loading states.
//

import SwiftUI

private enum SkeletonLayout {
    static let rowSpacing: CGFloat = 12
    static let avatarSize = EpacSpacing.avatar
    static let textSpacing: CGFloat = 6
    static let barCornerRadius = EpacCornerRadius.xs
    static let primaryHeight: CGFloat = 14
    static let titleMaxWidth: CGFloat = 180
    static let secondaryHeight: CGFloat = 10
    static let subtitleMaxWidth: CGFloat = 120
    static let rowVerticalPadding = EpacSpacing.xs
    static let compactBarWidth = EpacSpacing.avatar
    static let compactBarHeight: CGFloat = 12
    static let badgeCornerRadius: CGFloat = 6
    static let badgeWidth: CGFloat = 70
    static let badgeHeight: CGFloat = 18
    static let detailMaxWidth: CGFloat = 200
}

/// Placeholder MP row matching MemberRow dimensions.
struct MemberRowSkeleton: View {
    var body: some View {
        HStack(spacing: SkeletonLayout.rowSpacing) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: SkeletonLayout.avatarSize, height: SkeletonLayout.avatarSize)
            VStack(alignment: .leading, spacing: SkeletonLayout.textSpacing) {
                RoundedRectangle(cornerRadius: SkeletonLayout.barCornerRadius)
                    .fill(Color(.systemGray5))
                    .frame(height: SkeletonLayout.primaryHeight)
                    .frame(maxWidth: SkeletonLayout.titleMaxWidth)
                RoundedRectangle(cornerRadius: SkeletonLayout.barCornerRadius)
                    .fill(Color(.systemGray6))
                    .frame(height: SkeletonLayout.secondaryHeight)
                    .frame(maxWidth: SkeletonLayout.subtitleMaxWidth)
            }
            Spacer()
        }
        .padding(.vertical, SkeletonLayout.rowVerticalPadding)
    }
}

/// Placeholder bill row matching BillRow dimensions.
struct BillRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SkeletonLayout.textSpacing) {
            HStack {
                RoundedRectangle(cornerRadius: SkeletonLayout.barCornerRadius)
                    .fill(Color(.systemGray5))
                    .frame(width: SkeletonLayout.compactBarWidth, height: SkeletonLayout.compactBarHeight)
                Spacer()
                RoundedRectangle(cornerRadius: SkeletonLayout.badgeCornerRadius)
                    .fill(Color(.systemGray5))
                    .frame(width: SkeletonLayout.badgeWidth, height: SkeletonLayout.badgeHeight)
            }
            RoundedRectangle(cornerRadius: SkeletonLayout.barCornerRadius)
                .fill(Color(.systemGray5))
                .frame(height: SkeletonLayout.primaryHeight)
            RoundedRectangle(cornerRadius: SkeletonLayout.barCornerRadius)
                .fill(Color(.systemGray6))
                .frame(height: SkeletonLayout.primaryHeight)
                .frame(maxWidth: SkeletonLayout.detailMaxWidth)
        }
        .padding(.vertical, SkeletonLayout.rowVerticalPadding)
    }
}
